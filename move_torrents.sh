#!/bin/bash
# Move files matching a pattern from a local source folder to an SMB share.
# Runs at most once per day (tracked via date stamp file).
#
# Config is loaded from ~/.config/fast_t_mover/config (key=value), with built-in
# defaults if missing. The Swift menu-bar app writes that config file.
#
# Flags:
#   --debug / -d   Bypass the once-per-day lock, verbose output, loose match
#                  (also picks up files with the pattern anywhere in the name)

set -u

# --- Built-in defaults (used if config file missing) ----------------------
SOURCE_DIR="/Users/hanak/Downloads"
SMB_URL="smb://192.168.0.249/shdd"
DEST_SUBDIR="new-torrents"
PATTERN="*.torrent"
# Comma-separated list of Wi-Fi SSIDs the script is allowed to run on.
# Empty = run on any network (useful once a VPN provides reachability).
ALLOWED_SSIDS=""
# Minimum hours between successful runs. 0 = run on every tick.
# 24 = once daily (default); 1 = hourly, 4 = every 4 hours, etc.
INTERVAL_HOURS=24
# Only consider files modified within the last N days. 0 = no age limit.
# Useful when the source folder is huge/old.
MAX_AGE_DAYS=0
# --- Reliability tuning for flaky SMB sessions ----------------------------
# Number of attempts per file before giving up (one attempt = copy + verify).
# Between attempts we refresh the SMB session (remount) and back off.
RETRY_ATTEMPTS=3
# Seconds to wait after a failed attempt before retrying — lets a stale
# write-back session settle.
RETRY_DELAY_SECONDS=5
# Seconds to pause between files. Copying many files back-to-back can
# overload the SMB session (observed: bursts of md5 read-back failures).
# 0 = no pause. A small value trades speed for reliability.
INTER_FILE_DELAY_SECONDS=2

CONFIG_FILE="${HOME}/.config/fast_t_mover/config"
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
fi

# Derive mount point from SMB URL (last path segment).
SHARE_NAME="$(echo "${SMB_URL}" | sed -E 's#^smb://[^/]+/##' | sed 's#/.*##')"
MOUNT_POINT="/Volumes/${SHARE_NAME}"

STATE_DIR="${HOME}/.local/state/fast_t_mover"
LAST_RUN_FILE="${STATE_DIR}/last_run_ts"
LOG_FILE="${STATE_DIR}/torrent_mover.log"
STATS_FILE="${STATE_DIR}/stats"

DEBUG=0
FORCE=0
for arg in "$@"; do
    case "${arg}" in
        --debug|-d) DEBUG=1 ;;
        --force|-f) FORCE=1 ;;
    esac
done

mkdir -p "${STATE_DIR}"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "${msg}" >> "${LOG_FILE}"
    if [[ ${DEBUG} -eq 1 ]]; then
        echo "${msg}"
    fi
}

die() {
    log "ERROR: $*"
    exit 1
}

# Update lifetime + last-run statistics for the Settings hero card.
update_stats() {
    local moved_count="$1"
    local failed_count="$2"
    local prev_total=0
    if [[ -f "${STATS_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATS_FILE}"
        prev_total="${TOTAL_MOVED:-0}"
    fi
    local new_total=$(( prev_total + moved_count ))
    cat > "${STATS_FILE}" <<EOF
TOTAL_MOVED=${new_total}
LAST_RUN_TS=${NOW_TS}
LAST_RUN_MOVED=${moved_count}
LAST_RUN_FAILED=${failed_count}
EOF
}

# macOS notification banner. Writes a line to a queue file that the
# FastTMover menu-bar app watches and turns into a UNUserNotification
# (with an icon attachment matching `kind`).
# Falls back to osascript if the app isn't running (best effort).
# Usage: notify <kind> <title> <message>
#   kind = success | failure | info
notify() {
    local kind="${1:-info}"
    local title="${2:-FastTMover}"
    local msg="$3"
    # Sanitize the field separator out of values
    kind="${kind//|/-}"
    title="${title//|/-}"
    msg="${msg//|/-}"
    local queue="${STATE_DIR}/notify.queue"
    printf '%s|%s|%s\n' "${kind}" "${title}" "${msg}" >> "${queue}"
    if ! pgrep -q FastTMover; then
        FTM_TITLE="${title}" FTM_MSG="${msg}" osascript -e '
            display notification (system attribute "FTM_MSG") with title (system attribute "FTM_TITLE")
        ' >/dev/null 2>&1 || true
    fi
}

# --- Interval gate ---------------------------------------------------------
# --debug and --force both bypass this; LaunchAgent runs respect it.
NOW_TS="$(date +%s)"
if [[ ${DEBUG} -eq 0 && ${FORCE} -eq 0 && ${INTERVAL_HOURS} -gt 0 && -f "${LAST_RUN_FILE}" ]]; then
    LAST_TS="$(cat "${LAST_RUN_FILE}" 2>/dev/null || echo '0')"
    [[ "${LAST_TS}" =~ ^[0-9]+$ ]] || LAST_TS=0
    elapsed=$(( NOW_TS - LAST_TS ))
    min_interval=$(( INTERVAL_HOURS * 3600 ))
    if (( elapsed < min_interval )); then
        log "Ran $((elapsed / 60))m ago; min interval ${INTERVAL_HOURS}h. Exiting."
        exit 0
    fi
fi

log "=== Run start (debug=${DEBUG}) ==="
log "source=${SOURCE_DIR} smb=${SMB_URL} dest=${DEST_SUBDIR} pattern=${PATTERN}"

# --- Wi-Fi gate ------------------------------------------------------------
# Skip silently (without taking the daily lock) when not on an allowed
# network. Next launchd tick will retry. Empty list = no gate.
get_current_ssid() {
    local iface line
    iface=$(networksetup -listallhardwareports 2>/dev/null \
        | awk '/Hardware Port: Wi-Fi/{getline; print $2}')
    [[ -z "${iface}" ]] && return 1
    line=$(networksetup -getairportnetwork "${iface}" 2>/dev/null) || return 1
    if [[ "${line}" == *"Current Wi-Fi Network: "* ]]; then
        echo "${line#*Current Wi-Fi Network: }"
        return 0
    fi
    return 1
}

if [[ -n "${ALLOWED_SSIDS}" ]]; then
    current_ssid="$(get_current_ssid || true)"
    if [[ -z "${current_ssid}" ]]; then
        # macOS 14.4+ may redact SSID from background processes without
        # Location Services. Don't skip on unknown — let mount succeed or
        # soft-fail naturally. Worst case is a few extra mount attempts on
        # wrong networks; the alternative is silently never running.
        log "SSID unreadable (allowed: ${ALLOWED_SSIDS}); attempting mount anyway."
    else
        matched=0
        IFS=',' read -ra _allowed <<< "${ALLOWED_SSIDS}"
        for s in "${_allowed[@]}"; do
            # trim surrounding whitespace
            s="${s#"${s%%[![:space:]]*}"}"
            s="${s%"${s##*[![:space:]]}"}"
            [[ "${current_ssid}" == "${s}" ]] && { matched=1; break; }
        done
        if [[ ${matched} -eq 0 ]]; then
            log "Wi-Fi '${current_ssid}' not in allowed list (${ALLOWED_SSIDS}). Skipping, will retry."
            exit 0
        fi
        log "Wi-Fi '${current_ssid}' allowed."
    fi
fi

# --- Source check ----------------------------------------------------------
if [[ ! -d "${SOURCE_DIR}" ]]; then
    die "Source directory does not exist: ${SOURCE_DIR}"
fi

# In debug, also match files with the pattern body in the middle of name,
# so renamed test files (e.g. demo.torrent.py) get picked up.
if [[ ${DEBUG} -eq 1 ]]; then
    # Convert "*.torrent" -> "*torrent*" for loose match
    find_pattern="*${PATTERN//\*/}*"
else
    find_pattern="${PATTERN}"
fi

find_args=(-maxdepth 1 -type f -name "${find_pattern}")
if [[ ${MAX_AGE_DAYS} -gt 0 ]]; then
    find_args+=(-mtime "-${MAX_AGE_DAYS}")
fi
found_files=()
while IFS= read -r -d '' f; do
    found_files+=("$f")
done < <(find "${SOURCE_DIR}" "${find_args[@]}" -print0)

if [[ ${#found_files[@]} -eq 0 ]]; then
    log "No files matching ${find_pattern} in ${SOURCE_DIR}, nothing to do."
    notify "info" "FastTMover" "No ${PATTERN} files in $(basename "${SOURCE_DIR}")."
    echo "${NOW_TS}" > "${LAST_RUN_FILE}"
    update_stats 0 0
    exit 0
fi

log "Found ${#found_files[@]} file(s)."

# --- Mount SMB share -------------------------------------------------------
mount_share() {
    if [[ -d "${MOUNT_POINT}" ]] && mount | grep -q " on ${MOUNT_POINT} "; then
        log "Share already mounted at ${MOUNT_POINT}."
        return 0
    fi
    log "Mounting ${SMB_URL} ..."
    if ! osascript -e "mount volume \"${SMB_URL}\"" >/dev/null 2>&1; then
        return 1
    fi
    for _ in $(seq 1 20); do
        if mount | grep -q " on ${MOUNT_POINT} "; then
            log "Mounted at ${MOUNT_POINT}."
            return 0
        fi
        sleep 0.5
    done
    return 1
}

# Drop the current SMB session and establish a fresh one. Used to recover
# from a stale write-back session mid-batch (the failure mode where cp
# reports success but the bytes never land / can't be read back).
remount_share() {
    log "Remounting ${SMB_URL} (fresh session) ..."
    diskutil unmount "${MOUNT_POINT}" >/dev/null 2>&1 \
        || umount "${MOUNT_POINT}" >/dev/null 2>&1 || true
    sleep 1
    mount_share
}

if ! mount_share; then
    # Soft-fail: most likely off-network or VPN not up. Don't set the daily
    # lock — next launchd tick will retry.
    log "Could not mount ${SMB_URL} (off-network / VPN down?). Will retry on next tick."
    exit 0
fi

# Diagnostic: what is actually mounted at our expected point?
mount_line="$(mount | grep " on ${MOUNT_POINT} " || true)"
log "Mount: ${mount_line:-NONE — unexpected!}"
df_line="$(df -h "${MOUNT_POINT}" 2>/dev/null | tail -n 1 || true)"
log "df:    ${df_line:-N/A}"

# --- Ensure destination ----------------------------------------------------
DEST_DIR="${MOUNT_POINT}/${DEST_SUBDIR}"
if [[ ! -d "${DEST_DIR}" ]]; then
    mkdir -p "${DEST_DIR}" || die "Could not create ${DEST_DIR}"
    log "Created destination ${DEST_DIR}."
fi
# Show resolved canonical path so symlinks/automounts don't surprise us.
resolved_dest="$(cd "${DEST_DIR}" 2>/dev/null && pwd -P || echo "${DEST_DIR}")"
log "Destination resolved to: ${resolved_dest}"

# --- Move files (safe copy → verify → delete source) ----------------------
# Never delete the source unless the destination exists and has the same
# byte size. SMB's metadata-related mv warnings (xattrs/mode/times) are
# harmless but cause anxiety in the log; cp avoids them entirely.
moved=0
failed=0
for src in "${found_files[@]}"; do
    name="$(basename "${src}")"
    dest="${DEST_DIR}/${name}"
    if [[ -e "${dest}" ]]; then
        ts="$(date '+%Y%m%d-%H%M%S')"
        ext="${name##*.}"
        base="${name%.*}"
        dest="${DEST_DIR}/${base}.${ts}.${ext}"
    fi

    success=0
    for attempt in $(seq 1 "${RETRY_ATTEMPTS}"); do
        log "Copying (attempt ${attempt}/${RETRY_ATTEMPTS}): ${src}"
        log "     -> ${dest}"

        # 1. Copy
        if ! cp -- "${src}" "${dest}" 2>>"${LOG_FILE}"; then
            log "Attempt ${attempt}: copy failed for ${name}."
            rm -f -- "${dest}" 2>/dev/null   # remove any partial
        else
            # 2a. Quick size sanity (fast, uses cached stat).
            src_size=$(stat -f%z -- "${src}" 2>/dev/null || echo "")
            dest_size=$(stat -f%z -- "${dest}" 2>/dev/null || echo "")
            if [[ -z "${src_size}" || -z "${dest_size}" || "${src_size}" != "${dest_size}" ]]; then
                log "Attempt ${attempt}: size mismatch for ${name} (src=${src_size} dest=${dest_size})."
                rm -f -- "${dest}" 2>/dev/null
            else
                # 2b. Real content verify by md5. Forces an actual read from
                # the SMB share so we catch the 'cp succeeded into write-back
                # cache but bytes never landed' failure mode (stale session).
                src_md5=$(md5 -q -- "${src}" 2>/dev/null || echo "")
                dest_md5=$(md5 -q -- "${dest}" 2>/dev/null || echo "")
                if [[ -z "${src_md5}" || -z "${dest_md5}" || "${src_md5}" != "${dest_md5}" ]]; then
                    log "Attempt ${attempt}: content mismatch for ${name} (src md5=${src_md5:-?} dest md5=${dest_md5:-?})."
                    rm -f -- "${dest}" 2>/dev/null
                else
                    # 3. Verified — safe to remove source.
                    log "Verified: ${dest} (${dest_size} B, md5 ${dest_md5})"
                    if rm -- "${src}" 2>>"${LOG_FILE}"; then
                        log "Moved: ${name} -> ${dest}"
                    else
                        # Destination is good; only the local rm failed.
                        # Count as success but warn.
                        log "Moved ${name} -> ${dest} but could not delete source (will retry next run)."
                    fi
                    success=1
                    break
                fi
            fi
        fi

        # Attempt failed. If retries remain, refresh the SMB session and
        # back off before trying this file again.
        if (( attempt < RETRY_ATTEMPTS )); then
            log "Retrying ${name} after ${RETRY_DELAY_SECONDS}s (remounting first)."
            remount_share || log "Remount failed; will still retry the copy."
            sleep "${RETRY_DELAY_SECONDS}"
        fi
    done

    if (( success )); then
        moved=$((moved + 1))
    else
        log "GAVE UP on ${name} after ${RETRY_ATTEMPTS} attempts — source kept, will retry on next run."
        failed=$((failed + 1))
    fi

    # Gentle pause between files so we don't overload the SMB session.
    if (( INTER_FILE_DELAY_SECONDS > 0 )); then
        sleep "${INTER_FILE_DELAY_SECONDS}"
    fi
done

# Post-run sanity: list the destination directory so the user can see
# exactly what landed there.
log "Listing ${DEST_DIR} after run:"
if listing=$(ls -la "${DEST_DIR}" 2>&1); then
    while IFS= read -r line; do
        log "   ${line}"
    done <<< "${listing}"
else
    log "   (could not list — ${listing})"
fi

log "Done. moved=${moved} failed=${failed}"
if [[ ${failed} -gt 0 && ${moved} -gt 0 ]]; then
    notify "failure" "FastTMover" "Moved ${moved}, failed ${failed}. See log."
elif [[ ${failed} -gt 0 ]]; then
    notify "failure" "FastTMover" "Failed to move ${failed} file(s). See log."
else
    notify "success" "FastTMover" "Moved ${moved} file(s) to ${DEST_SUBDIR}."
fi
# Only take the interval lock on a fully clean run. If anything failed, leave
# the lock untouched so the next launchd tick retries the leftovers soon
# instead of waiting the full INTERVAL_HOURS.
if (( failed == 0 )); then
    echo "${NOW_TS}" > "${LAST_RUN_FILE}"
else
    log "Failures present — not taking the interval lock; next tick will retry."
fi
update_stats "${moved}" "${failed}"

exit 0
