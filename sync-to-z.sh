#!/usr/bin/env bash
set -euo pipefail

# Sync the local nix repo and bootstrap scripts to the z machine.

Z_HOST="z"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_SRC="${NIX_SRC:-${SCRIPT_DIR}/../z/nix}"

if [[ ! -d "$NIX_SRC" ]]; then
    echo "error: nix source not found at ${NIX_SRC}" >&2
    echo "  set NIX_SRC to the nix source directory" >&2
    exit 1
fi

echo "Syncing nix source from ${NIX_SRC} to ${Z_HOST}:nix..."
rsync -az --delete \
    --exclude='.git' \
    --exclude='build/' \
    --exclude='builddir/' \
    "${NIX_SRC}/" \
    "${Z_HOST}:nix/"

echo "Syncing bootstrap scripts to ${Z_HOST}:nix-bootstrap..."
rsync -az \
    "${SCRIPT_DIR}"/[0-9][0-9]-*.sh \
    "${SCRIPT_DIR}"/sync-to-z.sh \
    "${Z_HOST}:nix-bootstrap/"

echo "Sync complete."
echo "Next: ssh ${Z_HOST} and run scripts in ~/nix-bootstrap/"
