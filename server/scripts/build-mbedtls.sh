#!/usr/bin/env bash
# Build mbedTLS from source for cross-compilation targets (Android, HarmonyOS)
#
# Usage:
#   scripts/build-mbedtls.sh <target>
#   scripts/build-mbedtls.sh android arm64-v8a
#   scripts/build-mbedtls.sh ohos
#
# This script downloads mbedTLS 3.6.0 and builds it for the target platform.

set -e

TARGET="${1:-android}"
ABI="${2:-arm64-v8a}"

MBEDTLS_VERSION="3.6.0"
MBEDTLS_URL="https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-${MBEDTLS_VERSION}/mbedtls-${MBEDTLS_VERSION}.tar.bz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/deps/mbedtls-${MBEDTLS_VERSION}"
SOURCE_DIR="${BUILD_DIR}/src"
INSTALL_DIR="${PROJECT_ROOT}/third_party/mbedtls-prebuilt"

echo "============================================"
echo "Building mbedTLS ${MBEDTLS_VERSION} for ${TARGET}"
echo "============================================"

# Download source if not exists
if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "Downloading mbedTLS ${MBEDTLS_VERSION}..."
  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}"
  curl -L -o mbedtls.tar.bz "${MBEDTLS_URL}"
  tar -xjf mbedtls.tar.bz
  mv mbedtls-${MBEDTLS_VERSION} src
  rm mbedtls.tar.bz
fi

cd "${SOURCE_DIR}"
mkdir -p build && cd build

case "${TARGET}" in
  android)
    if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
      echo "Error: ANDROID_NDK_HOME is not set."
      echo "Please set ANDROID_NDK_HOME to your Android NDK path."
      exit 1
    fi

    : "${ANDROID_ABI:=${ABI}}"
    : "${ANDROID_API_LEVEL:=24}"

    TOOLCHAIN="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"

    echo "Building for Android ${ANDROID_ABI}, API ${ANDROID_API_LEVEL}..."

    cmake .. \
      -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
      -DANDROID_ABI="${ANDROID_ABI}" \
      -DANDROID_PLATFORM="android-${ANDROID_API_LEVEL}" \
      -DANDROID_STL=c++_static \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}/${TARGET}/${ANDROID_ABI}" \
      -DENABLE_PROGRAMS=OFF \
      -DENABLE_TESTING=OFF \
      -DMBEDTLS_FATAL_WARNINGS=OFF
    ;;
  ohos)
    if [[ -z "${OHOS_NDK_HOME:-}" ]]; then
      echo "Error: OHOS_NDK_HOME is not set."
      echo "Please set OHOS_NDK_HOME to your OpenHarmony native SDK path."
      exit 1
    fi

    TOOLCHAIN="${OHOS_NDK_HOME}/build/cmake/ohos.toolchain.cmake"

    echo "Building for HarmonyOS (aarch64)..."

    cmake .. \
      -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}/${TARGET}/arm64" \
      -DENABLE_PROGRAMS=OFF \
      -DENABLE_TESTING=OFF \
      -DMBEDTLS_FATAL_WARNINGS=OFF
    ;;
  *)
    echo "Unknown target: ${TARGET}"
    echo "Supported targets: android, ohos"
    exit 1
    ;;
esac

make -j$(nproc)
make install

echo ""
echo "============================================"
echo "mbedTLS built and installed to:"
echo "  ${INSTALL_DIR}/${TARGET}"
echo "============================================"
