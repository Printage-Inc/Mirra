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
STAGING_APP_DIR="${DIST_DIR}/staging/Mirra.app"
DMG_ROOT="${DIST_DIR}/dmg-root"
DMG_PATH="${PROJECT_DIR}/dist/${ARTIFACT_NAME}.dmg"
STAGING_DMG_PATH="${DIST_DIR}/Mirra-staging.dmg"
SOURCE_ARCHIVE_PATH="${DIST_DIR}/Mirra-${VERSION}-Source.zip"
IDENTITY="${CODESIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_FILE:-${PROJECT_DIR}/Resources/CableMirror.entitlements}"
WATCHER_ENTITLEMENTS_PATH="${WATCHER_ENTITLEMENTS_FILE:-${PROJECT_DIR}/Resources/CableMirrorDeviceWatcher.entitlements}"
ASSET_CATALOG_PATH="${PROJECT_DIR}/Resources/Assets.xcassets"
ASSET_INFO_PATH="${DIST_DIR}/asset-catalog-info.plist"
APP_ARCH="${APP_ARCH:-arm64}"

mkdir -p \
    "${STAGING_APP_DIR}/Contents/MacOS" \
    "${STAGING_APP_DIR}/Contents/Resources" \
    "${STAGING_APP_DIR}/Contents/Library/LaunchAgents" \
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
AIRPLAY_ARCH="${APP_ARCH}" "${PROJECT_DIR}/scripts/build-airplay-core.sh"
swift build --disable-sandbox -c release --arch "${APP_ARCH}"
BIN_DIR="$(swift build --disable-sandbox -c release --arch "${APP_ARCH}" --show-bin-path)"

ditto "${BIN_DIR}/Mirra" "${STAGING_APP_DIR}/Contents/MacOS/Mirra"
ditto "${BIN_DIR}/MirraDeviceWatcher" "${STAGING_APP_DIR}/Contents/MacOS/MirraDeviceWatcher"
ditto "${PROJECT_DIR}/Resources/Info.plist" "${STAGING_APP_DIR}/Contents/Info.plist"
ditto \
    "${PROJECT_DIR}/Resources/app.mirra.device-watcher.plist" \
    "${STAGING_APP_DIR}/Contents/Library/LaunchAgents/app.mirra.device-watcher.plist"
DEVELOPER_DIR="${DEVELOPER_DIR}" xcrun actool \
    "${ASSET_CATALOG_PATH}" \
    --compile "${STAGING_APP_DIR}/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "${ASSET_INFO_PATH}"
plutil -convert binary1 "${STAGING_APP_DIR}/Contents/Info.plist"
plutil -lint "${STAGING_APP_DIR}/Contents/Library/LaunchAgents/app.mirra.device-watcher.plist"

# SwiftPM emits ad-hoc signed executables. Remove those signatures before
# applying the distribution identity; replacing them in place with --force can
# leave a signature that only verifies from the signing process's cache.
for EXECUTABLE_PATH in \
    "${STAGING_APP_DIR}/Contents/MacOS/Mirra" \
    "${STAGING_APP_DIR}/Contents/MacOS/MirraDeviceWatcher"; do
    if codesign -d "${EXECUTABLE_PATH}" >/dev/null 2>&1; then
        codesign --remove-signature "${EXECUTABLE_PATH}"
    fi
done

if [[ "${IDENTITY}" == "-" ]]; then
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --entitlements "${WATCHER_ENTITLEMENTS_PATH}" \
        --sign "${IDENTITY}" \
        "${STAGING_APP_DIR}/Contents/MacOS/MirraDeviceWatcher"
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --entitlements "${ENTITLEMENTS_PATH}" \
        --sign "${IDENTITY}" \
        "${STAGING_APP_DIR}"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "${WATCHER_ENTITLEMENTS_PATH}" \
        --sign "${IDENTITY}" \
        "${STAGING_APP_DIR}/Contents/MacOS/MirraDeviceWatcher"
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "${ENTITLEMENTS_PATH}" \
        --sign "${IDENTITY}" \
        "${STAGING_APP_DIR}"
fi

# Verify the actual bytes on a fresh inode instead of relying on a result that
# may still be cached from the in-place signing operation.
codesign --verify --deep --strict --verbose=2 "${STAGING_APP_DIR}"
ditto "${STAGING_APP_DIR}" "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

ditto "${APP_DIR}" "${DMG_ROOT}/Mirra.app"
codesign --verify --deep --strict --verbose=2 "${DMG_ROOT}/Mirra.app"
"${PROJECT_DIR}/scripts/package-source.sh" "${SOURCE_ARCHIVE_PATH}"
ditto "${SOURCE_ARCHIVE_PATH}" "${DMG_ROOT}/Mirra-${VERSION}-Source.zip"
ditto "${PROJECT_DIR}/LICENSE" "${DMG_ROOT}/LICENSE.txt"
ditto "${PROJECT_DIR}/THIRD-PARTY-NOTICES.md" "${DMG_ROOT}/THIRD-PARTY-NOTICES.md"
ln -s /Applications "${DMG_ROOT}/Applications"
ditto "${APP_DIR}/Contents/Resources/AppIcon.icns" "${DMG_ROOT}/.VolumeIcon.icns"
xcrun SetFile -a C "${DMG_ROOT}"

hdiutil create \
    -volname "Mirra" \
    -srcfolder "${DMG_ROOT}" \
    -format UDZO \
    "${STAGING_DMG_PATH}"

if [[ "${IDENTITY}" != "-" ]]; then
    if codesign -d "${STAGING_DMG_PATH}" >/dev/null 2>&1; then
        codesign --remove-signature "${STAGING_DMG_PATH}"
    fi
    codesign \
        --force \
        --timestamp \
        --identifier "${ARTIFACT_NAME}" \
        --sign "${IDENTITY}" \
        "${STAGING_DMG_PATH}"
    codesign --verify --strict --verbose=2 "${STAGING_DMG_PATH}"
fi

ditto "${STAGING_DMG_PATH}" "${DMG_PATH}"
if [[ "${IDENTITY}" != "-" ]]; then
    codesign --verify --strict --verbose=2 "${DMG_PATH}"
fi

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
spctl --assess --type execute --verbose=2 "${APP_DIR}" || true

print "App: ${APP_DIR}"
print "DMG: ${DMG_PATH}"
print "Corresponding source: ${SOURCE_ARCHIVE_PATH}"
print "Entitlements: ${ENTITLEMENTS_PATH}"
print "Watcher entitlements: ${WATCHER_ENTITLEMENTS_PATH}"
print "Signing identity: ${IDENTITY}"
print "Architecture: ${APP_ARCH}"
