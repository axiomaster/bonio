#!/usr/bin/env bash
# Build hiclaw for macOS (arm64 or x86_64)
#
# Usage: scripts/build-macos.sh [--clean]
# Output: build/macos-arm64/hiclaw
#
# Requirements:
#   - CMake
#   - C++17 compiler (clang++ from Xcode Command Line Tools)
#   - mbedTLS bundled from third_party/mbedtls for HTTPS support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/macos-arm64"
BUILD_TYPE="${HICLAW_BUILD_TYPE:-Release}"

CLEAN_BUILD=false
for arg in "$@"; do
  if [[ "$arg" == "--clean" ]]; then
    CLEAN_BUILD=true
  fi
done

if ! command -v cmake &> /dev/null; then
  echo "Error: CMake not found. Install with: xcode-select --install"
  exit 1
fi

MBEDTLS_DIR="${PROJECT_ROOT}/third_party/mbedtls"
if [[ ! -f "${MBEDTLS_DIR}/CMakeLists.txt" ]]; then
  echo "Warning: mbedTLS not found. HTTPS will be disabled."
  echo "To enable HTTPS, clone mbedTLS:"
  echo "  git clone --depth 1 --branch v3.6.2 https://github.com/Mbed-TLS/mbedtls.git ${MBEDTLS_DIR}"
fi

echo "============================================"
echo "Building HiClaw for macOS"
echo "============================================"
echo "Build dir:  $BUILD_DIR"
echo "Build type: $BUILD_TYPE"
echo "Clean:      $CLEAN_BUILD"
echo "============================================"

if [[ "$CLEAN_BUILD" == "true" ]]; then
  echo "Cleaning build directory..."
  rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake -DCMAKE_BUILD_TYPE="$BUILD_TYPE" "$PROJECT_ROOT"
make -j"$(sysctl -n hw.ncpu)"

echo ""
echo "============================================"
echo "Build OK!"
echo "Binary: $BUILD_DIR/hiclaw"
echo "============================================"

# Copy to bin/
BIN_DIR="${PROJECT_ROOT}/bin"
mkdir -p "$BIN_DIR"
cp "$BUILD_DIR/hiclaw" "$BIN_DIR/hiclaw"
echo "Copied to $BIN_DIR/hiclaw"
