#!/usr/bin/env bash
set -euo pipefail

# Build SQLite 3.49.1 from source.
# Ubuntu 22.04 ships 3.37.2 which lacks sqlite3_error_offset()
# (added in 3.38.0), required by Nix's sqlite.cc.

SQLITE_VERSION="3490100"
SQLITE_URL="https://www.sqlite.org/2025/sqlite-autoconf-${SQLITE_VERSION}.tar.gz"
BUILD_DIR="${HOME}/sqlite-build"
PREFIX="/usr/local"
JOBS="$(nproc)"

# Skip if correct version is already installed
if "${PREFIX}/bin/sqlite3" --version 2>/dev/null | grep -q "3.49.1"; then
    echo "SQLite 3.49.1 already installed, skipping."
    exit 0
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f "sqlite-autoconf-${SQLITE_VERSION}.tar.gz" ]]; then
    echo "Downloading SQLite ${SQLITE_VERSION}..."
    wget -q "$SQLITE_URL"
fi

if [[ ! -d "sqlite-autoconf-${SQLITE_VERSION}" ]]; then
    echo "Extracting..."
    tar xf "sqlite-autoconf-${SQLITE_VERSION}.tar.gz"
fi

cd "sqlite-autoconf-${SQLITE_VERSION}"

echo "Configuring SQLite..."
./configure --prefix="$PREFIX"

echo "Building SQLite with ${JOBS} jobs..."
make -j "$JOBS"

echo "Installing SQLite..."
sudo make install
sudo ldconfig

echo "Phase 7 complete: SQLite ${SQLITE_VERSION} installed."
"${PREFIX}/bin/sqlite3" --version
