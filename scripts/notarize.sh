#!/bin/zsh

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    print "Usage: $0 /absolute/path/Mirra.dmg keychain-profile"
    exit 64
fi

DMG_PATH="$1"
KEYCHAIN_PROFILE="$2"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
ICON_SOURCE="${PROJECT_DIR}/Resources/MirraIcon.png"

if [[ ! -f "${DMG_PATH}" ]]; then
    print "DMG not found: ${DMG_PATH}"
    exit 66
fi

if [[ ! -f "${ICON_SOURCE}" ]]; then
    print "DMG icon source not found: ${ICON_SOURCE}"
    exit 66
fi

xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait
xcrun stapler staple "${DMG_PATH}"

# Finder stores a custom file icon in the DMG's resource fork. Add it only
# after stapling so the distributed file and its Finder thumbnail are final.
ICON_WORK_DIR="$(mktemp -d /private/tmp/mirra-dmg-icon.XXXXXX)"
ICON_COPY="${ICON_WORK_DIR}/MirraDMGIcon.png"
ICON_RESOURCE="${ICON_WORK_DIR}/MirraDMGIcon.r"
sips -z 512 512 "${ICON_SOURCE}" --out "${ICON_COPY}" >/dev/null
sips -i "${ICON_COPY}" >/dev/null
xcrun DeRez -only icns "${ICON_COPY}" > "${ICON_RESOURCE}"
xcrun Rez -append "${ICON_RESOURCE}" -o "${DMG_PATH}"
xcrun SetFile -a C "${DMG_PATH}"

xcrun stapler validate "${DMG_PATH}"
codesign --verify --strict --verbose=2 "${DMG_PATH}"
spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=4 \
    "${DMG_PATH}"
