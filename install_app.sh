#!/bin/bash
# Install or reinstall FastTMover.app into /Applications.
# Safe to run either way: if a running copy or an existing install is
# present, it is quit/removed first. No-ops cleanly on a fresh machine.

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="FastTMover"
DIST_APP="dist/${APP_NAME}.app"
TARGET_DIR="/Applications"
TARGET_APP="${TARGET_DIR}/${APP_NAME}.app"

echo "==> quitting running ${APP_NAME} (if any)"
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
# Wait for the process to actually exit; force-kill if still around.
for _ in 1 2 3 4 5; do
    pgrep -xq "${APP_NAME}" || break
    sleep 1
done
if pgrep -xq "${APP_NAME}"; then
    echo "    still alive, sending SIGTERM"
    pkill -x "${APP_NAME}" || true
    sleep 1
fi

echo "==> building"
./build_app.sh

if [[ ! -d "${DIST_APP}" ]]; then
    echo "Build did not produce ${DIST_APP}" >&2
    exit 1
fi

echo "==> installing to ${TARGET_APP}"
rm -rf "${TARGET_APP}"
cp -R "${DIST_APP}" "${TARGET_APP}"

# Force LaunchServices to re-read the bundle so Finder/Spotlight pick up
# any icon or metadata changes from this build.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "${TARGET_APP}" >/dev/null 2>&1 || true

echo "==> launching"
open "${TARGET_APP}"

echo
echo "Done. The FTM menu bar item should appear within a second or two."
echo "If the icon looks stale after an update, run:"
echo "    killall Dock Finder NotificationCenter usernoted"
