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

if ! mount_share; then
    # Soft-fail: most likely off-network or VPN not up. Don't set the daily
    # lock — next launchd tick will retry.
    log "Could not mount ${SMB_URL} (off-network / VPN down?). Will retry on next tick."
    exit 0
fi

# --- Ensure destination ----------------------------------------------------
DEST_DIR="${MOUNT_POINT}/${DEST_SUBDIR}"
if [[ ! -d "${DEST_DIR}" ]]; then
    mkdir -p "${DEST_DIR}" || die "Could not create ${DEST_DIR}"
    log "Created destination ${DEST_DIR}."
fi

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

    # 1. Copy
    if ! cp -- "${src}" "${dest}" 2>>"${LOG_FILE}"; then
        log "FAILED to copy: ${name} — source kept."
        rm -f -- "${dest}" 2>/dev/null   # remove any partial
        failed=$((failed + 1))
        continue
    fi

    # 2. Verify size
    src_size=$(stat -f%z -- "${src}" 2>/dev/null || echo "")
    dest_size=$(stat -f%z -- "${dest}" 2>/dev/null || echo "")
    if [[ -z "${src_size}" || -z "${dest_size}" || "${src_size}" != "${dest_size}" ]]; then
        log "Size mismatch for ${name} (src=${src_size} dest=${dest_size}) — source kept, partial dest removed."
        rm -f -- "${dest}" 2>/dev/null
        failed=$((failed + 1))
        continue
    fi

    # 3. Verified — safe to remove source
    if rm -- "${src}" 2>>"${LOG_FILE}"; then
        log "Moved: ${name}"
        moved=$((moved + 1))
    else
        # Destination is good; only the local rm failed. Count as success
        # (the goal was getting it onto the share) but warn.
        log "Moved ${name} but could not delete source (will retry next run)."
        moved=$((moved + 1))
    fi
done

log "Done. moved=${moved} failed=${failed}"
if [[ ${failed} -gt 0 && ${moved} -gt 0 ]]; then
    notify "failure" "FastTMover" "Moved ${moved}, failed ${failed}. See log."
elif [[ ${failed} -gt 0 ]]; then
    notify "failure" "FastTMover" "Failed to move ${failed} file(s). See log."
else
    notify "success" "FastTMover" "Moved ${moved} file(s) to ${DEST_SUBDIR}."
fi
echo "${NOW_TS}" > "${LAST_RUN_FILE}"

exit 0
