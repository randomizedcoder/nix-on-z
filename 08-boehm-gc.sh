#!/usr/bin/env bash
set -euo pipefail

# Build Boehm GC 8.2.8 from source with C++ support.
# Ubuntu 22.04 ships 8.0.6 where traceable_allocator<void>::value_type
# is private, causing compilation failures with Boost 1.87's
# container::allocator_traits. Fixed in 8.2.x.

GC_VERSION="8.2.8"
GC_URL="https://github.com/ivmai/bdwgc.git"
ATOMICOPS_URL="https://github.com/ivmai/libatomic_ops.git"
BUILD_DIR="${HOME}/bdwgc-build"
PREFIX="/usr/local"
JOBS="$(nproc)"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -d "bdwgc" ]]; then
    echo "Cloning Boehm GC ${GC_VERSION}..."
    git clone --depth 1 --branch "v${GC_VERSION}" "$GC_URL"
fi

cd bdwgc

if [[ ! -d "libatomic_ops" ]]; then
    echo "Cloning libatomic_ops..."
    git clone --depth 1 "$ATOMICOPS_URL"
fi

rm -rf build
mkdir build
cd build

echo "Configuring Boehm GC ${GC_VERSION} with C++ support..."
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -Dbuild_tests=OFF \
    -Denable_cplusplus=ON

echo "Building Boehm GC ${GC_VERSION} with ${JOBS} jobs..."
cmake --build . -j "$JOBS"

echo "Installing Boehm GC ${GC_VERSION}..."
sudo cmake --install .
sudo ldconfig

echo "Phase 8 complete: Boehm GC ${GC_VERSION} installed."
