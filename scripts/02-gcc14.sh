#!/usr/bin/env bash
set -euo pipefail

# Build GCC 14.2.0 from source for C++23 support.
# This is the longest phase (~1-3 hours on s390x).

GCC_VERSION="14.2.0"
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz"
BUILD_DIR="${HOME}/gcc-build"
SRC_DIR="${BUILD_DIR}/gcc-${GCC_VERSION}"
OBJ_DIR="${BUILD_DIR}/objdir"
PREFIX="/usr/local"
JOBS=1  # z machine has only 3.9 GiB RAM; >1 job OOMs during linking

# Skip if correct version is already installed
if "${PREFIX}/bin/gcc" --version 2>/dev/null | head -n 1 | grep -q "${GCC_VERSION}"; then
    echo "GCC ${GCC_VERSION} already installed, skipping."
    exit 0
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f "gcc-${GCC_VERSION}.tar.xz" ]]; then
    echo "Downloading GCC ${GCC_VERSION}..."
    wget -q "$GCC_URL"
fi

if [[ ! -d "$SRC_DIR" ]]; then
    echo "Extracting..."
    tar xf "gcc-${GCC_VERSION}.tar.xz"
fi

cd "$SRC_DIR"
echo "Downloading prerequisites..."
./contrib/download_prerequisites

mkdir -p "$OBJ_DIR"
cd "$OBJ_DIR"

echo "Configuring GCC ${GCC_VERSION} (languages: c,c++)..."
"${SRC_DIR}/configure" \
    --prefix="$PREFIX" \
    --enable-languages=c,c++ \
    --disable-multilib \
    --disable-bootstrap \
    --disable-nls \
    --with-system-zlib

echo "Building GCC ${GCC_VERSION} with ${JOBS} jobs..."
make -j "$JOBS"

echo "Installing GCC ${GCC_VERSION} to ${PREFIX}..."
sudo make install

echo "Updating shared library cache..."
sudo ldconfig

echo "Phase 2 complete: GCC ${GCC_VERSION} installed."
"${PREFIX}/bin/gcc" --version
