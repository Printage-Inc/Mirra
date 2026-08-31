#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

ARCH="${AIRPLAY_ARCH:-$(uname -m)}"
case "${ARCH}" in
    arm64) OPENSSL_TARGET="darwin64-arm64-cc" ;;
    x86_64) OPENSSL_TARGET="darwin64-x86_64-cc" ;;
    *) print "Unsupported AirPlay architecture: ${ARCH}"; exit 64 ;;
esac

for COMMAND_NAME in cmake make autoconf automake glibtoolize pkg-config perl patch rg; do
    if ! command -v "${COMMAND_NAME}" >/dev/null 2>&1; then
        print "Missing build dependency: ${COMMAND_NAME}"
        print "Install build tools with: HOMEBREW_NO_INSTALL_CLEANUP=1 brew install cmake autoconf automake libtool pkg-config ripgrep"
        exit 69
    fi
done

for SUBMODULE_FILE in \
    "${PROJECT_DIR}/Vendor/UxPlay/lib/raop.c" \
    "${PROJECT_DIR}/Vendor/AirPlayMacBridge/Sources/AirPlay/AirPlayEngine.mm" \
    "${PROJECT_DIR}/Vendor/OpenSSL/Configure" \
    "${PROJECT_DIR}/Vendor/libplist/configure.ac"; do
    if [[ ! -f "${SUBMODULE_FILE}" ]]; then
        print "Missing submodule source: ${SUBMODULE_FILE}"
        print "Run: git submodule update --init --recursive"
        exit 66
    fi
done

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
CLANG_BIN="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
CLANGXX_BIN="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
LIBTOOL_BIN="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/libtool"
CPU_COUNT="${BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || print 4)}"
CACHE_ROOT="${PROJECT_DIR}/.build/airplay-source-${ARCH}"
OPENSSL_PREFIX="${CACHE_ROOT}/openssl"
PLIST_PREFIX="${CACHE_ROOT}/libplist"
WORK_ROOT="$(mktemp -d "/private/tmp/mirra-airplay-${ARCH}.XXXXXX")"

mkdir -p "${CACHE_ROOT}" "${PROJECT_DIR}/.quarantine/generated-airplay"

if [[ ! -f "${OPENSSL_PREFIX}/lib/libcrypto.a" ]]; then
    print "▶ Building OpenSSL 3.5.8 for ${ARCH} / macOS 13+"
    OPENSSL_BUILD="${WORK_ROOT}/openssl-build"
    mkdir -p "${OPENSSL_BUILD}"
    (
        cd "${OPENSSL_BUILD}"
        export CC="${CLANG_BIN} -arch ${ARCH} -isysroot ${SDK_PATH} -mmacosx-version-min=13.0"
        export MACOSX_DEPLOYMENT_TARGET=13.0
        perl "${PROJECT_DIR}/Vendor/OpenSSL/Configure" \
            "${OPENSSL_TARGET}" \
            no-shared \
            no-tests \
            --prefix="${OPENSSL_PREFIX}" \
            --libdir=lib \
            --openssldir="${OPENSSL_PREFIX}/ssl"
        make -j"${CPU_COUNT}" build_sw
        make install_sw
    )
fi

if [[ ! -f "${PLIST_PREFIX}/lib/libplist-2.0.a" ]]; then
    print "▶ Building libplist 2.7.0 for ${ARCH} / macOS 13+"
    PLIST_STAGE="${WORK_ROOT}/libplist-src"
    ditto "${PROJECT_DIR}/Vendor/libplist" "${PLIST_STAGE}"
    if [[ -e "${PLIST_STAGE}/.git" ]]; then
        mv "${PLIST_STAGE}/.git" "${WORK_ROOT}/libplist-gitlink"
    fi
    print -n "2.7.0" > "${PLIST_STAGE}/.tarball-version"
    (
        cd "${PLIST_STAGE}"
        export CC="${CLANG_BIN} -arch ${ARCH} -isysroot ${SDK_PATH}"
        export CXX="${CLANGXX_BIN} -arch ${ARCH} -isysroot ${SDK_PATH}"
        export CFLAGS="-O2 -mmacosx-version-min=13.0"
        export CXXFLAGS="-O2 -mmacosx-version-min=13.0"
        export LDFLAGS="-arch ${ARCH} -isysroot ${SDK_PATH} -mmacosx-version-min=13.0"
        ./autogen.sh \
            --prefix="${PLIST_PREFIX}" \
            --disable-shared \
            --enable-static \
            --without-cython \
            --without-tools \
            --without-tests
        make -j"${CPU_COUNT}"
        make install
    )
fi

print "▶ Building the pinned UxPlay receiver core"
UXPLAY_STAGE="${WORK_ROOT}/uxplay-src"
UXPLAY_BUILD="${WORK_ROOT}/uxplay-build"
ditto "${PROJECT_DIR}/Vendor/UxPlay" "${UXPLAY_STAGE}"
if [[ -e "${UXPLAY_STAGE}/.git" ]]; then
    mv "${UXPLAY_STAGE}/.git" "${WORK_ROOT}/uxplay-gitlink"
fi

if (cd "${UXPLAY_STAGE}" && git apply --reverse --check "${PROJECT_DIR}/Patches/UxPlay-mirra-safety.patch" >/dev/null 2>&1); then
    print "  UxPlay safety patch is already present in the staged source"
else
    (cd "${UXPLAY_STAGE}" && git apply "${PROJECT_DIR}/Patches/UxPlay-mirra-safety.patch")
fi

if (cd "${UXPLAY_STAGE}" && git apply --reverse --check "${PROJECT_DIR}/Patches/UxPlay-mirra-security.patch" >/dev/null 2>&1); then
    print "  UxPlay security patch is already present in the staged source"
else
    (cd "${UXPLAY_STAGE}" && git apply "${PROJECT_DIR}/Patches/UxPlay-mirra-security.patch")
fi

if rg -q "ENTER PIN.*%s|pin_4 = 1234" "${UXPLAY_STAGE}/lib/raop_handlers.h"; then
    print "AirPlay core still contains a verification-code logging or fallback secret"
    exit 70
fi

# Only the protocol library is needed. The standalone UxPlay renderer pulls in
# GStreamer and creates an unrelated executable, so truncate the staged root
# CMake file before its renderer/app section.
sed -i '' '/add_subdirectory( renderers )/,$d' "${UXPLAY_STAGE}/CMakeLists.txt"
# UxPlay's macOS CMake file otherwise overwrites PKG_CONFIG_PATH with every
# common Homebrew path. Mirra needs the pinned, source-built headers and libs.
sed -i '' '/set( ENV{PKG_CONFIG_PATH}/s/^/# MIRRA preserves caller dependency roots: /' \
    "${UXPLAY_STAGE}/lib/CMakeLists.txt"

export PKG_CONFIG_PATH="${PLIST_PREFIX}/lib/pkgconfig:${OPENSSL_PREFIX}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${PLIST_PREFIX}/lib/pkgconfig:${OPENSSL_PREFIX}/lib/pkgconfig"
cmake \
    -S "${UXPLAY_STAGE}" \
    -B "${UXPLAY_BUILD}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_PREFIX_PATH="${PLIST_PREFIX};${OPENSSL_PREFIX}" \
    -DCMAKE_LIBRARY_PATH="${PLIST_PREFIX}/lib;${OPENSSL_PREFIX}/lib" \
    -DNO_MARCH_NATIVE=ON
cmake --build "${UXPLAY_BUILD}" --target airplay -j"${CPU_COUNT}"

print "▶ Building Mirra's VideoToolbox bridge"
BRIDGE_STAGE="${WORK_ROOT}/bridge-src"
BRIDGE_BUILD="${WORK_ROOT}/bridge-build"
HEADERS_DIR="${BRIDGE_BUILD}/Headers"
ditto "${PROJECT_DIR}/Vendor/AirPlayMacBridge" "${BRIDGE_STAGE}"
if [[ -e "${BRIDGE_STAGE}/.git" ]]; then
    mv "${BRIDGE_STAGE}/.git" "${WORK_ROOT}/bridge-gitlink"
fi

if (cd "${BRIDGE_STAGE}" && git apply --reverse --check "${PROJECT_DIR}/Patches/AirPlayMacBridge-verification-code.patch" >/dev/null 2>&1); then
    print "  Verification-code patch is already present in the staged source"
else
    (cd "${BRIDGE_STAGE}" && git apply "${PROJECT_DIR}/Patches/AirPlayMacBridge-verification-code.patch")
fi

if (cd "${BRIDGE_STAGE}" && git apply --reverse --check "${PROJECT_DIR}/Patches/AirPlayMacBridge-pairing-persistence.patch" >/dev/null 2>&1); then
    print "  Pairing-persistence patch is already present in the staged source"
else
    (cd "${BRIDGE_STAGE}" && git apply "${PROJECT_DIR}/Patches/AirPlayMacBridge-pairing-persistence.patch")
fi

if ! rg -q "onVerificationCode" "${BRIDGE_STAGE}/Sources/AirPlay/AirPlayEngine.h"; then
    print "Verification-code bridge patch did not update the public header"
    exit 70
fi

if ! rg -q 'raop_set_plist\(raop_, "pin", 0\)' "${BRIDGE_STAGE}/Sources/AirPlay/AirPlayEngine.mm"; then
    print "Pairing-persistence patch did not enable registered-client checks"
    exit 70
fi

mkdir -p "${BRIDGE_BUILD}" "${HEADERS_DIR}"
COMMON_FLAGS=(
    -arch "${ARCH}"
    -mmacosx-version-min=13.0
    -isysroot "${SDK_PATH}"
    -fobjc-arc
    -fblocks
    -std=c++20
    -I "${BRIDGE_STAGE}/Sources/AirPlay"
    -I "${UXPLAY_STAGE}/lib"
    -I "${UXPLAY_STAGE}/lib/playfair"
    -I "${UXPLAY_STAGE}/lib/llhttp"
    -I "${PLIST_PREFIX}/include"
    -I "${OPENSSL_PREFIX}/include"
)

"${CLANGXX_BIN}" "${COMMON_FLAGS[@]}" \
    -c "${BRIDGE_STAGE}/Sources/AirPlay/AirPlayEngine.mm" \
    -o "${BRIDGE_BUILD}/AirPlayEngine.o"
"${CLANGXX_BIN}" "${COMMON_FLAGS[@]}" \
    -c "${BRIDGE_STAGE}/Sources/AirPlay/H264DecoderVT.mm" \
    -o "${BRIDGE_BUILD}/H264DecoderVT.o"

AIRPLAY_ARCHIVE="$(find "${UXPLAY_BUILD}" -name libairplay.a -print -quit)"
DNSSD_ARCHIVE="$(find "${UXPLAY_BUILD}" -name libdnssd.a -print -quit)"
LLHTTP_ARCHIVE="$(find "${UXPLAY_BUILD}" -name libllhttp.a -print -quit)"
PLAYFAIR_ARCHIVE="$(find "${UXPLAY_BUILD}" -name libplayfair.a -print -quit)"

for ARCHIVE_PATH in "${AIRPLAY_ARCHIVE}" "${DNSSD_ARCHIVE}" "${LLHTTP_ARCHIVE}" "${PLAYFAIR_ARCHIVE}"; do
    [[ -f "${ARCHIVE_PATH}" ]] || { print "Missing UxPlay archive: ${ARCHIVE_PATH}"; exit 70; }
done

"${LIBTOOL_BIN}" -static \
    -o "${BRIDGE_BUILD}/libMirraAirPlay.a" \
    "${BRIDGE_BUILD}/AirPlayEngine.o" \
    "${BRIDGE_BUILD}/H264DecoderVT.o" \
    "${AIRPLAY_ARCHIVE}" \
    "${DNSSD_ARCHIVE}" \
    "${LLHTTP_ARCHIVE}" \
    "${PLAYFAIR_ARCHIVE}" \
    "${OPENSSL_PREFIX}/lib/libcrypto.a" \
    "${PLIST_PREFIX}/lib/libplist-2.0.a"

ditto "${BRIDGE_STAGE}/Sources/AirPlay/AirPlayEngine.h" "${HEADERS_DIR}/AirPlayEngine.h"
ditto "${PROJECT_DIR}/Resources/AirPlayBridgeHeaders/module.modulemap" "${HEADERS_DIR}/module.modulemap"

NEW_XCFRAMEWORK="${WORK_ROOT}/MirraAirPlay.xcframework"
xcodebuild -create-xcframework \
    -library "${BRIDGE_BUILD}/libMirraAirPlay.a" \
    -headers "${HEADERS_DIR}" \
    -output "${NEW_XCFRAMEWORK}"

FINAL_XCFRAMEWORK="${PROJECT_DIR}/.build/MirraAirPlay.xcframework"
if [[ -e "${FINAL_XCFRAMEWORK}" ]]; then
    ARCHIVE_STAMP="$(date +%Y%m%d-%H%M%S)-$$"
    mv "${FINAL_XCFRAMEWORK}" \
        "${PROJECT_DIR}/.quarantine/generated-airplay/MirraAirPlay-${ARCHIVE_STAMP}.xcframework"
fi
ditto "${NEW_XCFRAMEWORK}" "${FINAL_XCFRAMEWORK}"

print "✅ AirPlay core: ${FINAL_XCFRAMEWORK}"
print "   Architecture: ${ARCH}"
print "   Minimum macOS: 13.0"
print "   Build staging preserved at: ${WORK_ROOT}"
