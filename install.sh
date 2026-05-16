#!/bin/bash
# Install the torrent-mover launchd job for the current user.
# Idempotent — re-run any time after editing the plist or script.

set -euo pipefail

PROJECT_DIR="/Users/hanak/Documents/fast_t_mover"
PLIST_NAME="com.hanak.torrentmover.plist"
SRC_PLIST="${PROJECT_DIR}/${PLIST_NAME}"
DEST_PLIST="${HOME}/Library/LaunchAgents/${PLIST_NAME}"
SCRIPT="${PROJECT_DIR}/move_torrents.sh"

if [[ ! -f "${SRC_PLIST}" ]]; then
    echo "Missing ${SRC_PLIST}" >&2
    exit 1
fi
if [[ ! -f "${SCRIPT}" ]]; then
    echo "Missing ${SCRIPT}" >&2
    exit 1
fi

chmod +x "${SCRIPT}"
mkdir -p "${HOME}/Library/LaunchAgents"
mkdir -p "${HOME}/.local/state/fast_t_mover"

# Unload old version (ignore errors if not loaded)
if launchctl list | grep -q com.hanak.torrentmover; then
    echo "Unloading existing job..."
    launchctl unload "${DEST_PLIST}" 2>/dev/null || true
fi

cp "${SRC_PLIST}" "${DEST_PLIST}"
echo "Installed plist -> ${DEST_PLIST}"

launchctl load "${DEST_PLIST}"
echo "Loaded job com.hanak.torrentmover"

echo
echo "Useful commands:"
echo "  Debug run:    ${SCRIPT} --debug"
echo "  View log:     tail -f ~/.local/state/fast_t_mover/torrent_mover.log"
echo "  Reset lock:   rm ~/.local/state/fast_t_mover/last_run_date"
echo "  Uninstall:    launchctl unload ${DEST_PLIST} && rm ${DEST_PLIST}"
