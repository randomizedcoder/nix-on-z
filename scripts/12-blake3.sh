#!/usr/bin/env bash
set -euo pipefail

# Build BLAKE3 C library from source (not in Ubuntu 22.04).

BLAKE3_VERSION="1.8.2"
BLAKE3_URL="https://github.com/BLAKE3-team/BLAKE3/archive/refs/tags/${BLAKE3_VERSION}.tar.gz"
BUILD_DIR="${HOME}/blake3-build"
PREFIX="/usr/local"
JOBS="$(nproc)"

export CC=/usr/local/bin/gcc
export CXX=/usr/local/bin/g++

# Skip if correct version is already installed
if pkg-config --exact-version="${BLAKE3_VERSION}" libblake3 2>/dev/null; then
    echo "BLAKE3 ${BLAKE3_VERSION} already installed, skipping."
    exit 0
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f "${BLAKE3_VERSION}.tar.gz" ]]; then
    echo "Downloading BLAKE3 ${BLAKE3_VERSION}..."
    wget -q "$BLAKE3_URL"
fi

if [[ ! -d "BLAKE3-${BLAKE3_VERSION}" ]]; then
    echo "Extracting..."
    tar xf "${BLAKE3_VERSION}.tar.gz"
fi

mkdir -p "BLAKE3-${BLAKE3_VERSION}/c/build"
cd "BLAKE3-${BLAKE3_VERSION}/c/build"

echo "Configuring BLAKE3 ${BLAKE3_VERSION}..."
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBLAKE3_BUILD_SHARED_LIBS=ON

echo "Building BLAKE3 ${BLAKE3_VERSION} with ${JOBS} jobs..."
cmake --build . -j "$JOBS"

echo "Installing BLAKE3 ${BLAKE3_VERSION}..."
sudo cmake --install .
sudo ldconfig

echo "Phase 12 complete: BLAKE3 ${BLAKE3_VERSION} installed."
