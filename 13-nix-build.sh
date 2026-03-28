#!/usr/bin/env bash
set -euo pipefail

# Configure and build Nix from source using meson.
# Run from the nix source directory after sourcing 03-env.sh.

NIX_SRC="${HOME}/nix"
BUILD_DIR="${NIX_SRC}/build"
JOBS="$(nproc)"

if [[ ! -f "${NIX_SRC}/meson.build" ]]; then
    echo "error: run this script from the nix source directory or set NIX_SRC" >&2
    echo "  expected: ${NIX_SRC}/meson.build" >&2
    exit 1
fi

cd "$NIX_SRC"

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "Configuring Nix build..."
    meson setup "$BUILD_DIR" \
        --prefix=/usr/local \
        -Ddoc-gen=false \
        -Dunit-tests=false \
        -Dbindings=false \
        -Dbenchmarks=false \
        -Djson-schema-checks=false \
        -Dlibcmd:readline-flavor=readline \
        -Dlibstore:sandbox-shell=/usr/bin/bash-static
else
    echo "Build directory exists, reconfiguring..."
    meson setup "$BUILD_DIR" --reconfigure \
        --prefix=/usr/local \
        -Ddoc-gen=false \
        -Dunit-tests=false \
        -Dbindings=false \
        -Dbenchmarks=false \
        -Djson-schema-checks=false \
        -Dlibcmd:readline-flavor=readline \
        -Dlibstore:sandbox-shell=/usr/bin/bash-static
fi

echo "Building Nix with ${JOBS} jobs..."
meson compile -C "$BUILD_DIR" -j "$JOBS"

echo "Phase 13 complete: Nix built successfully."
echo "To install: sudo meson install -C ${BUILD_DIR}"
