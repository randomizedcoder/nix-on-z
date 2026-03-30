#!/usr/bin/env bash
set -euo pipefail

# Rebuild Nix with unit tests enabled, then run them.
# Run after sourcing 03-env.sh.

NIX_SRC="${HOME}/nix"
BUILD_DIR="${NIX_SRC}/build"
JOBS="$(nproc)"

cd "$NIX_SRC"

# Reconfigure with unit tests enabled
echo "Reconfiguring Nix with unit tests enabled..."
if [[ -d "$BUILD_DIR" ]]; then
    meson setup "$BUILD_DIR" --reconfigure \
        --prefix=/usr/local \
        -Ddoc-gen=false \
        -Dunit-tests=true \
        -Dbindings=false \
        -Dbenchmarks=false \
        -Djson-schema-checks=false \
        -Dlibcmd:readline-flavor=readline \
        -Dlibstore:sandbox-shell=/usr/bin/bash-static
else
    meson setup "$BUILD_DIR" \
        --prefix=/usr/local \
        -Ddoc-gen=false \
        -Dunit-tests=true \
        -Dbindings=false \
        -Dbenchmarks=false \
        -Djson-schema-checks=false \
        -Dlibcmd:readline-flavor=readline \
        -Dlibstore:sandbox-shell=/usr/bin/bash-static
fi

echo "Building Nix (with tests) using ${JOBS} jobs..."
meson compile -C "$BUILD_DIR" -j "$JOBS"

echo "Phase 16 complete: Nix built with unit tests."
echo "Run tests with: meson test -C ${BUILD_DIR}"
