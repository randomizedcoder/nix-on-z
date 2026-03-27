#!/usr/bin/env bash
set -euo pipefail

# Install test dependencies for running Nix's unit and functional tests.
# Both GoogleTest and RapidCheck must be built from source because
# Ubuntu 22.04's versions are incompatible with GCC 14 / C++23.

PREFIX="/usr/local"
JOBS="$(nproc)"

# GoogleTest 1.15.2 from source.
# Ubuntu 22.04's GoogleTest 1.11 triggers -Werror=undef with GCC 14
# (undefined GTEST_OS_WINDOWS_MOBILE macro in gmock-actions.h).
GTEST_VERSION="1.15.2"
GTEST_DIR="${HOME}/gtest-build"

if ! pkg-config --atleast-version=1.15 gtest 2>/dev/null; then
    echo "Building GoogleTest ${GTEST_VERSION}..."
    mkdir -p "$GTEST_DIR"
    cd "$GTEST_DIR"
    if [[ ! -d "googletest" ]]; then
        git clone --depth 1 --branch "v${GTEST_VERSION}" https://github.com/google/googletest.git
    fi
    cd googletest
    rm -rf build && mkdir build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release
    make -j "$JOBS"
    sudo make install
    echo "GoogleTest ${GTEST_VERSION} installed."
else
    echo "GoogleTest already installed, skipping."
fi

# RapidCheck from source (latest main branch).
# Ubuntu 22.04's RapidCheck has macro issues with C++23
# (RC_GTEST_TYPED_FIXTURE_PROP fails to compile).
RC_DIR="${HOME}/rapidcheck-build"

if [[ ! -f "${PREFIX}/lib/pkgconfig/rapidcheck.pc" ]] || \
   ! grep -q "${PREFIX}" "${PREFIX}/lib/pkgconfig/rapidcheck.pc" 2>/dev/null; then
    echo "Building RapidCheck from source..."
    mkdir -p "$RC_DIR"
    cd "$RC_DIR"
    if [[ ! -d "rapidcheck" ]]; then
        git clone --depth 1 https://github.com/emil-e/rapidcheck.git
    fi
    cd rapidcheck
    rm -rf build && mkdir build && cd build
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DRC_ENABLE_GTEST=ON \
        -DRC_ENABLE_GMOCK=ON
    make -j "$JOBS"
    sudo make install
    echo "RapidCheck installed."
else
    echo "RapidCheck already installed, skipping."
fi

echo "Phase 15 complete: test dependencies installed."
