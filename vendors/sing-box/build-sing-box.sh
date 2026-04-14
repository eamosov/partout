#!/bin/bash
#
# build-sing-box.sh
#
# Builds sing-box Go code as a C static library for Apple platforms.
# Called from Xcode Run Script build phase.
#
# Output: ${SING_BOX_OUTPUT_DIR}/lib/libsingbox.a
#         ${SING_BOX_OUTPUT_DIR}/include/sing_box.h
#
# Requires: Go toolchain (https://go.dev)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# SRCROOT is set by Xcode, otherwise resolve from script location
PASSEPARTOUT_ROOT="${SRCROOT:-${SCRIPT_DIR}/../../../..}"
SING_BOX_SRC="${PASSEPARTOUT_ROOT}/submodules/sing-box"

# Resolve to absolute path
SING_BOX_SRC="$(cd "${SING_BOX_SRC}" 2>/dev/null && pwd || echo "${SING_BOX_SRC}")"
SING_BOX_TAGS="with_utls"

# --- Output directory ---
SING_BOX_OUTPUT_DIR="${SING_BOX_OUTPUT_DIR:-${SCRIPT_DIR}/build}"
LIB_DIR="${SING_BOX_OUTPUT_DIR}/lib"
INCLUDE_DIR="${SING_BOX_OUTPUT_DIR}/include"
mkdir -p "${LIB_DIR}" "${INCLUDE_DIR}"

OUTPUT_LIB="${LIB_DIR}/libsingbox.a"
OUTPUT_HEADER="${INCLUDE_DIR}/sing_box.h"

# --- Find Go ---
GO_BIN=""
for candidate in "$(which go 2>/dev/null)" "/usr/local/go/bin/go" "/opt/homebrew/bin/go" "${HOME}/go/bin/go" "${HOME}/sdk/go/bin/go"; do
    if [ -x "$candidate" ]; then
        GO_BIN="$candidate"
        break
    fi
done

if [ -z "$GO_BIN" ]; then
    echo "error: Go toolchain not found. Install from https://go.dev" >&2
    exit 1
fi

echo "=== Building sing-box static library ==="
echo "Go: ${GO_BIN} ($(${GO_BIN} version))"
echo "Source: ${SING_BOX_SRC}"

# --- Check source ---
if [ ! -f "${SING_BOX_SRC}/go.mod" ]; then
    echo "error: sing-box source not found. Run: git submodule update --init submodules/sing-box" >&2
    exit 1
fi

# Copy C API wrapper into sing-box source if not present
if [ ! -f "${SING_BOX_SRC}/cmd/capi/main.go" ]; then
    CAPI_SRC="${SCRIPT_DIR}/capi/main.go"
    if [ -f "${CAPI_SRC}" ]; then
        echo "Copying C API wrapper from ${CAPI_SRC}"
        mkdir -p "${SING_BOX_SRC}/cmd/capi"
        cp "${CAPI_SRC}" "${SING_BOX_SRC}/cmd/capi/main.go"
    else
        echo "error: C API wrapper not found at ${SING_BOX_SRC}/cmd/capi/main.go or ${CAPI_SRC}" >&2
        exit 1
    fi
fi

# --- Skip if up to date ---
if [ -f "${OUTPUT_LIB}" ]; then
    NEWER=$(find "${SING_BOX_SRC}/cmd/capi" -name '*.go' -newer "${OUTPUT_LIB}" 2>/dev/null | head -1)
    if [ -z "${NEWER}" ]; then
        echo "sing-box library is up to date, skipping"
        exit 0
    fi
fi

# --- Platform detection ---
PLATFORM="${PLATFORM_NAME:-macosx}"
TARGET_ARCH="${ARCHS:-$(uname -m)}"
TARGET_ARCH=$(echo "${TARGET_ARCH}" | awk '{print $1}')

case "${TARGET_ARCH}" in
    arm64)  GOARCH="arm64" ;;
    x86_64) GOARCH="amd64" ;;
    *)      GOARCH="arm64" ;;
esac

case "${PLATFORM}" in
    iphoneos)
        GOOS="ios"
        SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
        CGO_FLAGS="-isysroot ${SDK_PATH} -arch ${TARGET_ARCH} -mios-version-min=16.0"
        ;;
    iphonesimulator)
        GOOS="ios"
        SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
        CGO_FLAGS="-isysroot ${SDK_PATH} -arch ${TARGET_ARCH} -mios-simulator-version-min=16.0"
        ;;
    appletvos)
        GOOS="ios"
        SDK_PATH="$(xcrun --sdk appletvos --show-sdk-path)"
        CGO_FLAGS="-isysroot ${SDK_PATH} -arch ${TARGET_ARCH} -mtvos-version-min=17.0"
        ;;
    appletvsimulator)
        GOOS="ios"
        SDK_PATH="$(xcrun --sdk appletvsimulator --show-sdk-path)"
        CGO_FLAGS="-isysroot ${SDK_PATH} -arch ${TARGET_ARCH} -mappletvos-simulator-version-min=17.0"
        ;;
    macosx|*)
        GOOS="darwin"
        SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
        CGO_FLAGS="-isysroot ${SDK_PATH} -arch ${TARGET_ARCH} -mmacosx-version-min=13.0"
        ;;
esac

echo "Platform: ${PLATFORM} (${GOOS}/${GOARCH})"

# --- Build ---
cd "${SING_BOX_SRC}"

CGO_ENABLED=1 \
GOOS="${GOOS}" \
GOARCH="${GOARCH}" \
CGO_CFLAGS="${CGO_FLAGS}" \
CGO_LDFLAGS="${CGO_FLAGS}" \
CC="$(xcrun --find clang)" \
CXX="$(xcrun --find clang++)" \
"${GO_BIN}" build \
    -tags "${SING_BOX_TAGS}" \
    -buildmode=c-archive \
    -trimpath \
    -o "${OUTPUT_LIB}" \
    ./cmd/capi

# Go generates header next to .a
GENERATED_HEADER="${OUTPUT_LIB%.a}.h"
if [ -f "${GENERATED_HEADER}" ]; then
    cp "${GENERATED_HEADER}" "${OUTPUT_HEADER}"
fi

echo "=== sing-box built: ${OUTPUT_LIB} ($(wc -c < "${OUTPUT_LIB}" | tr -d ' ') bytes) ==="
