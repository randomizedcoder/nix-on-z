#!/usr/bin/env bash
set -euo pipefail

# Sync the local nix source, rapidcheck source, and bootstrap scripts
# to the z machine (ssh z). See README.md "Development Setup" for details.
#
# Expects the following layout on the workstation:
#   ~/Downloads/nix-on-z/    (this repo)
#   ~/Downloads/nix/         (patched Nix source)
#   ~/Downloads/rapidcheck/  (RapidCheck fork, nix-on-z branch)
#
# Override paths with environment variables if your layout differs:
#   NIX_SRC=~/my/nix RAPIDCHECK_SRC=~/my/rc ./sync-to-z.sh

Z_HOST="z"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_SRC="${NIX_SRC:-${SCRIPT_DIR}/../nix}"
RAPIDCHECK_SRC="${RAPIDCHECK_SRC:-${SCRIPT_DIR}/../rapidcheck}"

# --- Nix source ---
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

# --- RapidCheck source ---
if [[ -d "$RAPIDCHECK_SRC" ]]; then
    echo "Syncing rapidcheck from ${RAPIDCHECK_SRC} to ${Z_HOST}:rapidcheck..."
    rsync -az --delete \
        --exclude='.git' \
        --exclude='build/' \
        "${RAPIDCHECK_SRC}/" \
        "${Z_HOST}:rapidcheck/"
else
    echo "warning: rapidcheck source not found at ${RAPIDCHECK_SRC}, skipping"
fi

# --- Bootstrap scripts ---
echo "Syncing bootstrap scripts to ${Z_HOST}:nix-on-z..."
rsync -az \
    "${SCRIPT_DIR}"/[0-9][0-9]-*.sh \
    "${SCRIPT_DIR}"/sync-to-z.sh \
    "${Z_HOST}:nix-on-z/"

echo "Sync complete."
echo "Next: ssh ${Z_HOST} and run scripts in ~/nix-on-z/"
