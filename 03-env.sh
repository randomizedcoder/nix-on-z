#!/usr/bin/env bash
# Source this file, do not execute it: source 03-env.sh
#
# Sets up the environment for building dependencies and Nix with GCC 14.
# Source this after phase 2 (GCC 14) and before every subsequent phase.

# GCC 14
export CC=/usr/local/bin/gcc
export CXX=/usr/local/bin/g++

# Binaries
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

# Libraries built from source
export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# pkg-config (include /usr/local/share/pkgconfig for nlohmann_json)
export PKG_CONFIG_PATH="/usr/local/share/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Boost
export BOOST_ROOT="/usr/local"

echo "Environment configured for Nix s390x build."
echo "  CC=$CC"
echo "  CXX=$CXX"
echo "  PATH includes: /usr/local/bin, ~/.local/bin"
