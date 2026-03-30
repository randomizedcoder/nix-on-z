#!/usr/bin/env bash
set -euo pipefail

# Install Ubuntu 22.04 packages needed to bootstrap Nix on s390x.
# Run as root: sudo bash 00-apt-deps.sh
#
# These satisfy ~10 of Nix's build dependencies directly.
# The remaining deps (GCC 14, Boost 1.87, nlohmann_json 3.11,
# toml11 4.x, SQLite 3.49, Boehm GC 8.2, curl 8.17, libgit2 1.9,
# libseccomp 2.5.5, BLAKE3 1.8) are built from source in later phases.

if [[ $EUID -ne 0 ]]; then
    echo "error: must run as root (use sudo)" >&2
    exit 1
fi

apt-get update

# Remove busybox-static if present — Ubuntu's busybox doesn't work
# in the Nix store (argv[0] applet lookup fails), and its presence
# causes meson to set sandbox_shell, making tests fail instead of skip.
apt-get remove -y busybox-static 2>/dev/null || true

apt-get install -y \
    ninja-build \
    pkg-config \
    bison \
    flex \
    libsqlite3-dev \
    libsodium-dev \
    libarchive-dev \
    libssl-dev \
    libbrotli-dev \
    libreadline-dev \
    libedit-dev \
    cmake \
    autoconf \
    automake \
    libtool \
    gperf \
    python3-pip \
    texinfo \
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    wget \
    xz-utils \
    zlib1g-dev \
    git \
    m4 \
    gettext \
    lowdown \
    bash-static

echo "Phase 0 complete: apt dependencies installed."
