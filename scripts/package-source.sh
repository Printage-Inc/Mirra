#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_PATH="${1:-}"

if [[ -z "${OUTPUT_PATH}" ]]; then
    print "Usage: $0 /absolute/path/to/Mirra-Source.zip"
    exit 64
fi

if [[ "${OUTPUT_PATH}" != /* ]]; then
    print "Source archive output must be an absolute path: ${OUTPUT_PATH}"
    exit 64
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Resources/Info.plist")"
WORK_ROOT="$(mktemp -d "/private/tmp/mirra-source.XXXXXX")"
SOURCE_ROOT="${WORK_ROOT}/Mirra-${VERSION}-Source"
mkdir -p "${SOURCE_ROOT}" "${OUTPUT_PATH:h}"

copy_tracked_files() {
    local REPOSITORY_ROOT="$1"
    local DESTINATION_ROOT="$2"

    (
        cd "${REPOSITORY_ROOT}"
        while IFS= read -r -d '' RELATIVE_PATH; do
            SOURCE_PATH="${REPOSITORY_ROOT}/${RELATIVE_PATH}"
            # A tracked directory is a gitlink. Mirra packages each required
            # top-level submodule explicitly below; nested vendor gitlinks are
            # intentionally not duplicated.
            if [[ -d "${SOURCE_PATH}" ]]; then
                continue
            fi
            if [[ ! -f "${SOURCE_PATH}" ]]; then
                print "Tracked source is unavailable: ${SOURCE_PATH}"
                print "Run: git submodule update --init --recursive"
                exit 66
            fi
            TARGET_PATH="${DESTINATION_ROOT}/${RELATIVE_PATH}"
            mkdir -p "${TARGET_PATH:h}"
            ditto "${SOURCE_PATH}" "${TARGET_PATH}"
        done < <(git ls-files -z)
    )
}

copy_tracked_files "${PROJECT_DIR}" "${SOURCE_ROOT}"
for SUBMODULE_PATH in \
    Vendor/UxPlay \
    Vendor/AirPlayMacBridge \
    Vendor/OpenSSL \
    Vendor/libplist; do
    copy_tracked_files \
        "${PROJECT_DIR}/${SUBMODULE_PATH}" \
        "${SOURCE_ROOT}/${SUBMODULE_PATH}"
done

ditto -c -k --sequesterRsrc --keepParent "${SOURCE_ROOT}" "${OUTPUT_PATH}"

print "Source: ${OUTPUT_PATH}"
print "Source staging preserved at: ${WORK_ROOT}"
