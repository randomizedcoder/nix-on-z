#!/usr/bin/env bash
set -euo pipefail

# Sync the local nix repo and bootstrap scripts to the z machine.

Z_HOST="z"

echo "Syncing nix source to ${Z_HOST}:nix..."
rsync -az --delete \
    --exclude='.git' \
    --exclude='build/' \
    --exclude='builddir/' \
    ~/Downloads/z/nix/ \
    "${Z_HOST}:nix/"

echo "Syncing bootstrap scripts to ${Z_HOST}:nix-bootstrap..."
rsync -az \
    ~/Downloads/z/00-apt-deps.sh \
    ~/Downloads/z/01-meson-pip.sh \
    ~/Downloads/z/02-gcc14.sh \
    ~/Downloads/z/03-env.sh \
    ~/Downloads/z/04-boost.sh \
    ~/Downloads/z/05-nlohmann-json.sh \
    ~/Downloads/z/06-toml11.sh \
    ~/Downloads/z/07-sqlite.sh \
    ~/Downloads/z/08-boehm-gc.sh \
    ~/Downloads/z/09-curl.sh \
    ~/Downloads/z/10-libgit2.sh \
    ~/Downloads/z/11-libseccomp.sh \
    ~/Downloads/z/12-blake3.sh \
    ~/Downloads/z/13-nix-build.sh \
    ~/Downloads/z/14-nix-install.sh \
    "${Z_HOST}:nix-bootstrap/"

echo "Syncing plan document..."
rsync -az \
    ~/Downloads/z/nix-s390x-bootstrap.md \
    "${Z_HOST}:nix-bootstrap/"

echo "Sync complete."
echo "Next: ssh ${Z_HOST} and run scripts in ~/nix-bootstrap/"
