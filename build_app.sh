#!/bin/bash
# Build HPA.app (Hanak Personal Assistant) from the SwiftPM target.
# Output: ./dist/HPA.app
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="HPA"
BUNDLE_ID="com.hanak.hpa"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"

echo "==> swift build (release)"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
    echo "Build did not produce ${BIN_PATH}" >&2
    exit 1
fi

echo "==> assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}"             "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "Info.plist"              "${APP_DIR}/Contents/Info.plist"
cp "move_torrents.sh"        "${APP_DIR}/Contents/Resources/move_torrents.sh"
chmod +x "${APP_DIR}/Contents/Resources/move_torrents.sh"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# --- Icon ----------------------------------------------------------------
ICON_MASTER="${DIST_DIR}/AppIcon_1024.png"
ICONSET="${DIST_DIR}/AppIcon.iconset"
ICNS_OUT="${APP_DIR}/Contents/Resources/AppIcon.icns"

echo "==> generating app icon"
swift tools/generate_icon.swift "${ICON_MASTER}" >/dev/null
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"
for sz in 16 32 128 256 512; do
    sips -z $sz $sz                    "${ICON_MASTER}" \
        --out "${ICONSET}/icon_${sz}x${sz}.png" >/dev/null
    twox=$((sz * 2))
    sips -z $twox $twox                "${ICON_MASTER}" \
        --out "${ICONSET}/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET}" -o "${ICNS_OUT}"
echo "icon -> ${ICNS_OUT}"

# Ad-hoc sign so macOS lets it run without quarantine pain on first launch.
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || \
    echo "(codesign ad-hoc failed; app will still launch but may prompt)"

echo
echo "Built: ${APP_DIR}"
echo "Install:  cp -R ${APP_DIR} /Applications/"
echo "Run dev:  open ${APP_DIR}"
