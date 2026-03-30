#!/usr/bin/env bash
set -euo pipefail

# Install nlohmann_json 3.11.3 from source.
# Ubuntu 22.04 ships 3.10.5 which fails to compile with GCC 14
# due to stricter C++23 implicit conversion rules in std::pair.

NLOHMANN_VERSION="3.11.3"
NLOHMANN_URL="https://github.com/nlohmann/json/releases/download/v${NLOHMANN_VERSION}/json.tar.xz"
BUILD_DIR="${HOME}/nlohmann-build"
PREFIX="/usr/local"

# Skip if correct version is already installed
if pkg-config --exact-version="${NLOHMANN_VERSION}" nlohmann_json 2>/dev/null; then
    echo "nlohmann_json ${NLOHMANN_VERSION} already installed, skipping."
    exit 0
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f "json.tar.xz" ]]; then
    echo "Downloading nlohmann_json ${NLOHMANN_VERSION}..."
    wget -q "$NLOHMANN_URL"
fi

if [[ ! -d "json" ]]; then
    echo "Extracting..."
    tar xf "json.tar.xz"
fi

mkdir -p "json/build"
cd "json/build"

echo "Configuring nlohmann_json ${NLOHMANN_VERSION}..."
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DJSON_BuildTests=OFF

echo "Installing nlohmann_json ${NLOHMANN_VERSION}..."
sudo cmake --install .

echo "Phase 5 complete: nlohmann_json ${NLOHMANN_VERSION} installed."
