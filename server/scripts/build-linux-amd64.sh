#!/usr/bin/env bash
# Build hiclaw for Linux x86_64 (amd64)
#
# Usage: scripts/build-linux-amd64.sh [--clean]
# Output: server/build/linux-amd64/hiclaw
#
# Requirements:
#   - CMake
#   - Ninja (or make)
#   - C++17 compiler (g++ or clang++)
#   - mbedTLS bundled from third_party/mbedtls for HTTPS support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT is server/ directory (parent of scripts/)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/linux-amd64"
BUILD_TYPE="${HICLAW_BUILD_TYPE:-Release}"

# Parse arguments
CLEAN_BUILD=false
for arg in "$@"; do
  if [[ "$arg" == "--clean" ]]; then
    CLEAN_BUILD=true
  fi
done

# Check for dependencies
if ! command -v cmake &> /dev/null; then
  echo "Error: CMake not found. Install with: apt install cmake"
  exit 1
fi

# Check for mbedTLS
MBEDTLS_DIR="${PROJECT_ROOT}/third_party/mbedtls"
if [[ ! -f "${MBEDTLS_DIR}/CMakeLists.txt" ]]; then
  echo "Warning: mbedTLS not found. HTTPS will be disabled."
  echo "To enable HTTPS, clone mbedTLS:"
  echo "  git clone --depth 1 --branch v3.6.2 https://github.com/Mbed-TLS/mbedtls.git ${MBEDTLS_DIR}"
fi

# Determine generator
GENERATOR="Ninja"
if command -v ninja &> /dev/null; then
  NINJA_EXE="ninja"
else
  echo "Ninja not found, using Unix Makefiles"
  GENERATOR="Unix Makefiles"
  NINJA_EXE="make"
fi

echo "============================================"
echo "Building HiClaw for Linux x86_64"
echo "============================================"
echo "Build dir:  $BUILD_DIR"
echo "Build type: $BUILD_TYPE"
echo "Generator:  $GENERATOR"
echo "Clean:      $CLEAN_BUILD"
echo "============================================"

# Clean build directory if requested or if CMakeCache.txt exists with old config
if [[ "$CLEAN_BUILD" == "true" ]]; then
  echo "Cleaning build directory..."
  rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Always reconfigure to pick up new dependencies
cmake -G "$GENERATOR" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  "$PROJECT_ROOT"

if [[ "$GENERATOR" == "Ninja" ]]; then
  ninja
else
  make -j$(nproc)
fi

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
