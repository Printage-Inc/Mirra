#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${PROJECT_DIR}/.build/ModuleCache}"
export CLANG_MODULE_CACHE_PATH

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Resources/Info.plist")"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_NAME="Mirra-${VERSION}-${STAMP}"
DIST_DIR="${PROJECT_DIR}/dist/${ARTIFACT_NAME}"
APP_DIR="${DIST_DIR}/Mirra.app"
DMG_ROOT="${DIST_DIR}/dmg-root"
DMG_PATH="${PROJECT_DIR}/dist/${ARTIFACT_NAME}.dmg"
IDENTITY="${CODESIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_FILE:-${PROJECT_DIR}/Resources/CableMirror.entitlements}"
WATCHER_ENTITLEMENTS_PATH="${WATCHER_ENTITLEMENTS_FILE:-${PROJECT_DIR}/Resources/CableMirrorDeviceWatcher.entitlements}"
ASSET_CATALOG_PATH="${PROJECT_DIR}/Resources/Assets.xcassets"
ASSET_INFO_PATH="${DIST_DIR}/asset-catalog-info.plist"

mkdir -p \
    "${APP_DIR}/Contents/MacOS" \
    "${APP_DIR}/Contents/Resources" \
    "${APP_DIR}/Contents/Library/LaunchAgents" \
    "${DMG_ROOT}" \
    "${CLANG_MODULE_CACHE_PATH}"

if [[ ! -f "${ENTITLEMENTS_PATH}" ]]; then
    print "Entitlements file not found: ${ENTITLEMENTS_PATH}"
    exit 66
fi

if [[ ! -f "${WATCHER_ENTITLEMENTS_PATH}" ]]; then
    print "Watcher entitlements file not found: ${WATCHER_ENTITLEMENTS_PATH}"
    exit 66
fi

cd "${PROJECT_DIR}"
swift build --disable-sandbox -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build --disable-sandbox -c release --arch arm64 --arch x86_64 --show-bin-path)"

ditto "${BIN_DIR}/Mirra" "${APP_DIR}/Contents/MacOS/Mirra"
ditto "${BIN_DIR}/MirraDeviceWatcher" "${APP_DIR}/Contents/MacOS/MirraDeviceWatcher"
ditto "${PROJECT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
ditto \
    "${PROJECT_DIR}/Resources/app.mirra.device-watcher.plist" \
    "${APP_DIR}/Contents/Library/LaunchAgents/app.mirra.device-watcher.plist"
DEVELOPER_DIR="${DEVELOPER_DIR}" xcrun actool \
    "${ASSET_CATALOG_PATH}" \
    --compile "${APP_DIR}/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "${ASSET_INFO_PATH}"
plutil -convert binary1 "${APP_DIR}/Contents/Info.plist"
plutil -lint "${APP_DIR}/Contents/Library/LaunchAgents/app.mirra.device-watcher.plist"

if [[ "${IDENTITY}" == "-" ]]; then
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --entitlements "${WATCHER_ENTITLEMENTS_PATH}" \
        --sign "${IDENTITY}" \
        "${APP_DIR}/Contents/MacOS/MirraDeviceWatcher"
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --entitlements "${ENTITLEMENTS_PATH}" \
        --sign "${IDENTITY}" \
        "${APP_DIR}"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "${WATCHER_ENTITLEMENTS_PATH}" \
        --sign "${IDENTITY}" \
        "${APP_DIR}/Contents/MacOS/MirraDeviceWatcher"
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "${ENTITLEMENTS_PATH}" \
        --sign "${IDENTITY}" \
        "${APP_DIR}"
fi

ditto "${APP_DIR}" "${DMG_ROOT}/Mirra.app"
ln -s /Applications "${DMG_ROOT}/Applications"
ditto "${APP_DIR}/Contents/Resources/AppIcon.icns" "${DMG_ROOT}/.VolumeIcon.icns"
xcrun SetFile -a C "${DMG_ROOT}"

hdiutil create \
    -volname "Mirra" \
    -srcfolder "${DMG_ROOT}" \
    -format UDZO \
    "${DMG_PATH}"

if [[ "${IDENTITY}" != "-" ]]; then
    codesign \
        --force \
        --timestamp \
        --sign "${IDENTITY}" \
        "${DMG_PATH}"
    codesign --verify --strict --verbose=2 "${DMG_PATH}"
fi

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
spctl --assess --type execute --verbose=2 "${APP_DIR}" || true

print "App: ${APP_DIR}"
print "DMG: ${DMG_PATH}"
print "Entitlements: ${ENTITLEMENTS_PATH}"
print "Watcher entitlements: ${WATCHER_ENTITLEMENTS_PATH}"
print "Signing identity: ${IDENTITY}"
