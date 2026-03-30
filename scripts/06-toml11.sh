#!/usr/bin/env bash
set -euo pipefail

# Install toml11 4.4.0 from source.
# Ubuntu 22.04's libtoml11-dev (3.7.0) lacks cmake config files,
# so meson's cmake dependency detection cannot find it.

TOML11_VERSION="4.4.0"
TOML11_URL="https://github.com/ToruNiina/toml11.git"
BUILD_DIR="${HOME}/toml11-build"
PREFIX="/usr/local"

# Skip if correct version is already installed
if [[ -f "${PREFIX}/lib/cmake/toml11/toml11Config.cmake" ]] && \
   grep -q "${TOML11_VERSION}" "${PREFIX}/lib/cmake/toml11/toml11ConfigVersion.cmake" 2>/dev/null; then
    echo "toml11 ${TOML11_VERSION} already installed, skipping."
    exit 0
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -d "toml11" ]]; then
    echo "Cloning toml11 ${TOML11_VERSION}..."
    git clone --depth 1 --branch "v${TOML11_VERSION}" "$TOML11_URL"
fi

mkdir -p "toml11/build"
cd "toml11/build"

echo "Configuring toml11 ${TOML11_VERSION}..."
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"

echo "Installing toml11 ${TOML11_VERSION}..."
sudo cmake --install .

echo "Phase 6 complete: toml11 ${TOML11_VERSION} installed."
