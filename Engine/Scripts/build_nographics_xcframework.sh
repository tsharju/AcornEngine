#!/usr/bin/env bash
set -euo pipefail

# Build NoGraphicsAPI + NoGraphicsAPIUtility static libraries for macOS (arm64)
# and iOS (arm64, Metal 4 physical devices) and bundle them into an XCFramework.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${ENGINE_DIR}/Dependencies/NoGraphicsAPI"
OUT_DIR="${ENGINE_DIR}/Binaries"
XCFRAMEWORK_PATH="${OUT_DIR}/NoGraphicsAPI.xcframework"

if [[ ! -d "${SRC_DIR}" ]]; then
    echo "error: Vendored NoGraphicsAPI not found at ${SRC_DIR}" >&2
    exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "error: cmake is required to build NoGraphicsAPI" >&2
    exit 1
fi

unset SDKROOT CC CXX CPATH LIBRARY_PATH

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nographics_build.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

build_slice() {
    local name="$1"
    shift
    local build_dir="${WORK_DIR}/build-${name}"
    local install_dir="${WORK_DIR}/install-${name}"
    local combined_dir="${WORK_DIR}/combined-${name}"

    echo "==> Configuring NoGraphicsAPI (${name})..."
    cmake -S "${SRC_DIR}" -B "${build_dir}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DNOGRAPHICSAPI_BUILD_EXAMPLES=OFF \
        -DNOGRAPHICSAPI_BUILD_TESTS=OFF \
        "$@"

    echo "==> Building NoGraphicsAPI (${name})..."
    cmake --build "${build_dir}" --config Release -j"$(sysctl -n hw.ncpu)"

    echo "==> Installing NoGraphicsAPI (${name})..."
    cmake --install "${build_dir}" --config Release --prefix "${install_dir}"

    mkdir -p "${combined_dir}"
    xcrun libtool -static -o "${combined_dir}/libNoGraphicsAPI.a" \
        "${install_dir}/lib/libNoGraphicsAPI.a" \
        "${install_dir}/lib/libNoGraphicsAPIUtility_allocators.a" \
        "${install_dir}/lib/libNoGraphicsAPIUtility_textures.a" \
        "${install_dir}/lib/libNoGraphicsAPIUtility_uploads.a"
}

build_slice "macos" \
    -DCMAKE_OSX_SYSROOT=macosx \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0

build_slice "ios" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0

# Stage clean headers (NoGraphicsAPI + NoGraphicsAPIUtility) without exporting a
# Swift-visible modulemap so NoGraphicsAPI/types.h typedefs stay isolated inside C++.
HEADERS_DIR="${WORK_DIR}/headers"
mkdir -p "${HEADERS_DIR}"
cp -R "${WORK_DIR}/install-macos/include/NoGraphicsAPI" "${HEADERS_DIR}/"
cp -R "${WORK_DIR}/install-macos/include/NoGraphicsAPIUtility" "${HEADERS_DIR}/"

mkdir -p "${OUT_DIR}"
rm -rf "${XCFRAMEWORK_PATH}"

echo "==> Creating ${XCFRAMEWORK_PATH}..."
xcodebuild -create-xcframework \
    -library "${WORK_DIR}/combined-macos/libNoGraphicsAPI.a" \
    -headers "${HEADERS_DIR}" \
    -library "${WORK_DIR}/combined-ios/libNoGraphicsAPI.a" \
    -headers "${HEADERS_DIR}" \
    -output "${XCFRAMEWORK_PATH}"

echo "==> Successfully built ${XCFRAMEWORK_PATH}"
