#!/usr/bin/env bash
set -euo pipefail

# Build libgit2 1.9.0 from source (Ubuntu 22.04 has 1.1).

LIBGIT2_VERSION="1.9.0"
LIBGIT2_URL="https://github.com/libgit2/libgit2/archive/refs/tags/v${LIBGIT2_VERSION}.tar.gz"
BUILD_DIR="${HOME}/libgit2-build"
PREFIX="/usr/local"
JOBS="$(nproc)"

export CC=/usr/local/bin/gcc
export CXX=/usr/local/bin/g++

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f "v${LIBGIT2_VERSION}.tar.gz" ]]; then
    echo "Downloading libgit2 ${LIBGIT2_VERSION}..."
    wget -q "$LIBGIT2_URL"
fi

if [[ ! -d "libgit2-${LIBGIT2_VERSION}" ]]; then
    echo "Extracting..."
    tar xf "v${LIBGIT2_VERSION}.tar.gz"
fi

mkdir -p "libgit2-${LIBGIT2_VERSION}/build"
cd "libgit2-${LIBGIT2_VERSION}/build"

echo "Configuring libgit2 ${LIBGIT2_VERSION}..."
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF

echo "Building libgit2 ${LIBGIT2_VERSION} with ${JOBS} jobs..."
cmake --build . -j "$JOBS"

echo "Installing libgit2 ${LIBGIT2_VERSION}..."
sudo cmake --install .
sudo ldconfig

echo "Phase 10 complete: libgit2 ${LIBGIT2_VERSION} installed."
