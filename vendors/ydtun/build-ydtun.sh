#!/bin/bash
#
# build-ydtun.sh
#
# Builds ydtun Rust code as a C static library for Apple platforms.
# Called from Xcode Run Script build phase.
#
# Output: ${YDTUN_OUTPUT_DIR}/lib/libydtun.a
#
# Requires:
#   - Rust toolchain with Apple targets (rustup target add aarch64-apple-ios)
#   - libvpx for iOS (cross-compiled automatically if needed)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASSEPARTOUT_ROOT="${SRCROOT:-${SCRIPT_DIR}/../../../..}"
YDTUN_SRC="${PASSEPARTOUT_ROOT}/submodules/ydtun"

# Resolve to absolute path
YDTUN_SRC="$(cd "${YDTUN_SRC}" 2>/dev/null && pwd || echo "${YDTUN_SRC}")"

# --- Output directory ---
YDTUN_OUTPUT_DIR="${YDTUN_OUTPUT_DIR:-${SCRIPT_DIR}/build}"
LIB_DIR="${YDTUN_OUTPUT_DIR}/lib"
INCLUDE_DIR="${YDTUN_OUTPUT_DIR}/include"
VPX_DIR="${YDTUN_OUTPUT_DIR}/vpx"
mkdir -p "${LIB_DIR}" "${INCLUDE_DIR}" "${VPX_DIR}"

OUTPUT_LIB="${LIB_DIR}/libydtun.a"

# --- Find Rust toolchain ---
CARGO_BIN=""
for candidate in "$(which cargo 2>/dev/null)" "${HOME}/.cargo/bin/cargo" "/opt/homebrew/bin/cargo"; do
    if [ -x "$candidate" ]; then
        CARGO_BIN="$candidate"
        break
    fi
done

if [ -z "$CARGO_BIN" ]; then
    echo "error: Rust toolchain not found. Install from https://rustup.rs" >&2
    exit 1
fi

echo "=== Building ydtun static library ==="
echo "Cargo: ${CARGO_BIN} ($(${CARGO_BIN} --version))"
echo "Source: ${YDTUN_SRC}"

# --- Check source ---
if [ ! -f "${YDTUN_SRC}/Cargo.toml" ]; then
    echo "error: ydtun source not found. Run: git submodule update --init submodules/ydtun" >&2
    exit 1
fi

# --- Skip if up to date ---
if [ -f "${OUTPUT_LIB}" ]; then
    NEWER=$(find "${YDTUN_SRC}/src" -name '*.rs' -newer "${OUTPUT_LIB}" 2>/dev/null | head -1)
    if [ -z "${NEWER}" ]; then
        echo "ydtun library is up to date, skipping"
        exit 0
    fi
fi

# --- Platform detection ---
PLATFORM="${PLATFORM_NAME:-iphoneos}"
TARGET_ARCH="${ARCHS:-arm64}"
TARGET_ARCH=$(echo "${TARGET_ARCH}" | awk '{print $1}')

case "${PLATFORM}" in
    iphoneos)
        RUST_TARGET="aarch64-apple-ios"
        VPX_ARCH="arm64-darwin-gcc"
        IOS_SDK="iphoneos"
        MIN_VERSION="-mios-version-min=16.0"
        ;;
    iphonesimulator)
        if [ "${TARGET_ARCH}" = "x86_64" ]; then
            RUST_TARGET="x86_64-apple-ios"
            VPX_ARCH="x86_64-iphonesimulator-gcc"
        else
            RUST_TARGET="aarch64-apple-ios-sim"
            VPX_ARCH="arm64-iphonesimulator-gcc"
        fi
        IOS_SDK="iphonesimulator"
        MIN_VERSION="-mios-simulator-version-min=16.0"
        ;;
    macosx|*)
        if [ "${TARGET_ARCH}" = "x86_64" ]; then
            RUST_TARGET="x86_64-apple-darwin"
        else
            RUST_TARGET="aarch64-apple-darwin"
        fi
        VPX_ARCH=""
        IOS_SDK=""
        ;;
esac

echo "Platform: ${PLATFORM} (${RUST_TARGET})"

# --- Ensure Rust target is installed ---
${CARGO_BIN} target list --installed 2>/dev/null | grep -q "${RUST_TARGET}" || {
    echo "Installing Rust target: ${RUST_TARGET}"
    rustup target add "${RUST_TARGET}" 2>/dev/null || true
}

# --- Build libvpx for iOS if needed ---
VPX_LIB="${VPX_DIR}/${RUST_TARGET}/lib/libvpx.a"
VPX_INCLUDE="${VPX_DIR}/${RUST_TARGET}/include"

if [ -n "${IOS_SDK}" ] && [ ! -f "${VPX_LIB}" ]; then
    echo "=== Building libvpx for ${RUST_TARGET} ==="

    # Download libvpx source if needed
    VPX_SRC_DIR="${YDTUN_OUTPUT_DIR}/libvpx-src"
    if [ ! -f "${VPX_SRC_DIR}/configure" ]; then
        echo "Downloading libvpx source..."
        VPX_VERSION="1.14.1"
        VPX_URL="https://chromium.googlesource.com/webm/libvpx/+archive/v${VPX_VERSION}.tar.gz"
        mkdir -p "${VPX_SRC_DIR}"
        curl -sL "${VPX_URL}" -o "/tmp/libvpx.tar.gz"
        tar xzf /tmp/libvpx.tar.gz -C "${VPX_SRC_DIR}" 2>/dev/null
        if [ ! -f "${VPX_SRC_DIR}/configure" ]; then
            echo "error: Failed to download libvpx source from ${VPX_URL}" >&2
            exit 1
        fi
    fi

    SDK_PATH="$(xcrun --sdk ${IOS_SDK} --show-sdk-path)"
    VPX_BUILD_DIR="${VPX_DIR}/${RUST_TARGET}/build"
    mkdir -p "${VPX_BUILD_DIR}" "${VPX_DIR}/${RUST_TARGET}/lib" "${VPX_INCLUDE}"

    cd "${VPX_BUILD_DIR}"

    IOS_CC="$(xcrun --sdk ${IOS_SDK} --find clang)"
    IOS_CXX="$(xcrun --sdk ${IOS_SDK} --find clang++)"

    CC="${IOS_CC}" \
    CXX="${IOS_CXX}" \
    CROSS="${IOS_CC} -arch ${TARGET_ARCH} -isysroot ${SDK_PATH} ${MIN_VERSION}" \
    CFLAGS="-arch ${TARGET_ARCH} -isysroot ${SDK_PATH} ${MIN_VERSION} -O3" \
    LDFLAGS="-arch ${TARGET_ARCH} -isysroot ${SDK_PATH} ${MIN_VERSION}" \
    "${VPX_SRC_DIR}/configure" \
        --target="${VPX_ARCH}" \
        --enable-static \
        --disable-shared \
        --disable-examples \
        --disable-tools \
        --disable-docs \
        --disable-unit-tests \
        --enable-vp8 \
        --enable-vp9 \
        --enable-pic \
        --extra-cflags="-arch ${TARGET_ARCH} -isysroot ${SDK_PATH} ${MIN_VERSION}" \
        --prefix="${VPX_DIR}/${RUST_TARGET}" \
        2>&1

    make -j$(sysctl -n hw.ncpu) 2>&1
    make install 2>&1

    echo "=== libvpx built: ${VPX_LIB} ==="
fi

# --- Build ydtun static library ---
cd "${YDTUN_SRC}"

export VPX_STATIC=1
if [ -n "${IOS_SDK}" ]; then
    export VPX_LIB_DIR="${VPX_DIR}/${RUST_TARGET}/lib"
    export VPX_INCLUDE_DIR="${VPX_DIR}/${RUST_TARGET}/include"
fi

${CARGO_BIN} build \
    --lib \
    --release \
    --target "${RUST_TARGET}" \
    --no-default-features \
    --features port-forward

# Copy static library to output
BUILT_LIB="${YDTUN_SRC}/target/${RUST_TARGET}/release/libydtun.a"
if [ ! -f "${BUILT_LIB}" ]; then
    echo "error: Build succeeded but library not found at ${BUILT_LIB}" >&2
    exit 1
fi

cp "${BUILT_LIB}" "${OUTPUT_LIB}"

echo "=== ydtun built: ${OUTPUT_LIB} ($(wc -c < "${OUTPUT_LIB}" | tr -d ' ') bytes) ==="
