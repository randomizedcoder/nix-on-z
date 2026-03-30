#!/usr/bin/env bash
set -euo pipefail

# Install test dependencies for running Nix's unit and functional tests.
#
# jq is built from source because Nix's functional tests assume modern
# tooling (jq >= 1.7 for .[]? try-iterate syntax). Ubuntu 22.04 ships 1.6.
#
# GoogleTest and RapidCheck must be built from source because Ubuntu 22.04's
# versions are incompatible with GCC 14 / C++23.

PREFIX="/usr/local"
JOBS="$(nproc)"

# jq 1.7.1 from source.
# Nix's functional tests use jq 1.7+ syntax (e.g., `.info.[].ca`).
# Ubuntu 22.04 ships jq 1.6 which does not support this.
JQ_VERSION="1.7.1"
JQ_DIR="${HOME}/jq-build"

if ! jq --version 2>/dev/null | grep -q "jq-1\.[7-9]"; then
    echo "Building jq ${JQ_VERSION}..."
    mkdir -p "$JQ_DIR"
    cd "$JQ_DIR"
    if [[ ! -d "jq" ]]; then
        git clone --depth 1 --branch "jq-${JQ_VERSION}" https://github.com/jqlang/jq.git
    fi
    cd jq
    git submodule update --init
    autoreconf -i
    ./configure --with-oniguruma=builtin --prefix="$PREFIX"
    make -j "$JOBS"
    sudo make install
    echo "jq ${JQ_VERSION} installed."
else
    echo "jq >= 1.7 already installed, skipping."
fi

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

# RapidCheck from source (nix-on-z fork with -fPIC fix).
# Ubuntu 22.04's RapidCheck has macro issues with C++23
# (RC_GTEST_TYPED_FIXTURE_PROP fails to compile).
# The fork adds CMAKE_POSITION_INDEPENDENT_CODE so the static library can be
# linked into Nix's shared test-support libraries without text relocations,
# which cause SIGSEGV on s390x.
RC_DIR="${HOME}/rapidcheck-build"

if [[ ! -f "${PREFIX}/lib/pkgconfig/rapidcheck.pc" ]] || \
   ! grep -q "${PREFIX}" "${PREFIX}/lib/pkgconfig/rapidcheck.pc" 2>/dev/null; then
    echo "Building RapidCheck from source (nix-on-z fork)..."
    mkdir -p "$RC_DIR"
    cd "$RC_DIR"
    if [[ ! -d "rapidcheck" ]]; then
        git clone --depth 1 --branch nix-on-z https://github.com/randomizedcoder/rapidcheck.git
    fi
    cd rapidcheck
    rm -rf build && mkdir build && cd build
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DRC_ENABLE_GTEST=ON \
        -DRC_ENABLE_GMOCK=ON \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    make -j "$JOBS"
    sudo make install
    # RapidCheck's cmake install produces a .pc file with an empty Libs: line,
    # so meson falls back to finding the system librapidcheck.a at
    # /usr/lib/s390x-linux-gnu/. Replace it with our PIC-built version.
    if [[ -f /usr/lib/s390x-linux-gnu/librapidcheck.a ]]; then
        sudo cp "${PREFIX}/lib/librapidcheck.a" /usr/lib/s390x-linux-gnu/librapidcheck.a
        echo "Replaced system librapidcheck.a with PIC version."
    fi
    echo "RapidCheck installed."
else
    echo "RapidCheck already installed, skipping."
fi

echo "Phase 15 complete: test dependencies installed."
