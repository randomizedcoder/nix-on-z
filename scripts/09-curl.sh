#!/usr/bin/env bash
set -euo pipefail

# Build libcurl 8.17.0 from source.
# Ubuntu 22.04 ships 7.81. Nix requires >= 8.17.0.

CURL_VERSION="8.17.0"
CURL_URL="https://curl.se/download/curl-${CURL_VERSION}.tar.xz"
BUILD_DIR="${HOME}/curl-build"
PREFIX="/usr/local"
JOBS="$(nproc)"

export CC=/usr/local/bin/gcc
export CXX=/usr/local/bin/g++

# Skip if correct version is already installed
if "${PREFIX}/bin/curl" --version 2>/dev/null | head -n 1 | grep -q "${CURL_VERSION}"; then
    echo "curl ${CURL_VERSION} already installed, skipping."
    exit 0
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f "curl-${CURL_VERSION}.tar.xz" ]]; then
    echo "Downloading curl ${CURL_VERSION}..."
    wget -q "$CURL_URL"
fi

if [[ ! -d "curl-${CURL_VERSION}" ]]; then
    echo "Extracting..."
    tar xf "curl-${CURL_VERSION}.tar.xz"
fi

cd "curl-${CURL_VERSION}"

echo "Configuring curl ${CURL_VERSION}..."
./configure \
    --prefix="$PREFIX" \
    --with-openssl \
    --without-libpsl

echo "Building curl ${CURL_VERSION} with ${JOBS} jobs..."
make -j "$JOBS"

echo "Installing curl ${CURL_VERSION}..."
sudo make install
sudo ldconfig

echo "Phase 9 complete: curl ${CURL_VERSION} installed."
"${PREFIX}/bin/curl" --version | head -n 1
