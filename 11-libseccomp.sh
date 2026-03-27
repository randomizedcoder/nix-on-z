#!/usr/bin/env bash
set -euo pipefail

# Build libseccomp 2.5.5 from source (Ubuntu 22.04 has 2.5.3).

SECCOMP_VERSION="2.5.5"
SECCOMP_URL="https://github.com/seccomp/libseccomp/releases/download/v${SECCOMP_VERSION}/libseccomp-${SECCOMP_VERSION}.tar.gz"
BUILD_DIR="${HOME}/seccomp-build"
PREFIX="/usr/local"
JOBS="$(nproc)"

export CC=/usr/local/bin/gcc
export CXX=/usr/local/bin/g++

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f "libseccomp-${SECCOMP_VERSION}.tar.gz" ]]; then
    echo "Downloading libseccomp ${SECCOMP_VERSION}..."
    wget -q "$SECCOMP_URL"
fi

if [[ ! -d "libseccomp-${SECCOMP_VERSION}" ]]; then
    echo "Extracting..."
    tar xf "libseccomp-${SECCOMP_VERSION}.tar.gz"
fi

cd "libseccomp-${SECCOMP_VERSION}"

echo "Configuring libseccomp ${SECCOMP_VERSION}..."
./configure --prefix="$PREFIX"

echo "Building libseccomp ${SECCOMP_VERSION} with ${JOBS} jobs..."
make -j "$JOBS"

echo "Installing libseccomp ${SECCOMP_VERSION}..."
sudo make install
sudo ldconfig

echo "Phase 11 complete: libseccomp ${SECCOMP_VERSION} installed."
