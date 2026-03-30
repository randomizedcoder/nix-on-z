#!/usr/bin/env bash
set -euo pipefail

# Build Boost 1.87.0 from source using GCC 14.
# Ubuntu 22.04 ships Boost 1.74 which is too old for Nix.

BOOST_VERSION="1.87.0"
BOOST_UNDERSCORE="1_87_0"
BOOST_URL="https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_UNDERSCORE}.tar.bz2"
BUILD_DIR="${HOME}/boost-build"
PREFIX="/usr/local"
JOBS=1  # z machine has only 3.9 GiB RAM; >1 job OOMs during linking

export CC=/usr/local/bin/gcc
export CXX=/usr/local/bin/g++

# Skip if correct version is already installed
if [[ -f "${PREFIX}/include/boost/version.hpp" ]] && \
   grep -q "BOOST_LIB_VERSION \"${BOOST_UNDERSCORE}\"" "${PREFIX}/include/boost/version.hpp" 2>/dev/null; then
    echo "Boost ${BOOST_VERSION} already installed, skipping."
    exit 0
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f "boost_${BOOST_UNDERSCORE}.tar.bz2" ]]; then
    echo "Downloading Boost ${BOOST_VERSION}..."
    wget -q "$BOOST_URL"
fi

if [[ ! -d "boost_${BOOST_UNDERSCORE}" ]]; then
    echo "Extracting..."
    tar xf "boost_${BOOST_UNDERSCORE}.tar.bz2"
fi

cd "boost_${BOOST_UNDERSCORE}"

echo "Bootstrapping Boost build system..."
./bootstrap.sh --prefix="$PREFIX" --with-toolset=gcc

echo "Building and installing Boost ${BOOST_VERSION} with ${JOBS} jobs..."
# Note: install requires sudo because --prefix=/usr/local
sudo LD_LIBRARY_PATH="/usr/local/lib64:/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    ./b2 -j "$JOBS" \
    toolset=gcc \
    cxxflags="-std=c++17" \
    link=shared,static \
    threading=multi \
    variant=release \
    install --prefix="$PREFIX"

sudo ldconfig

echo "Phase 4 complete: Boost ${BOOST_VERSION} installed."
