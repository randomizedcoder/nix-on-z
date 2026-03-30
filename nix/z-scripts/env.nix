# Shared environment setup for s390x bootstrap scripts.
# Replaces 03-env.sh — interpolated into every script with needsEnv = true,
# and also emitted as a standalone 03-env.sh for interactive use on z.
''
# GCC 14
export CC=/usr/local/bin/gcc
export CXX=/usr/local/bin/g++

# Binaries
export PATH="''${HOME}/.local/bin:/usr/local/bin:''${PATH}"

# Libraries built from source
export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# pkg-config (include /usr/local/share/pkgconfig for nlohmann_json)
export PKG_CONFIG_PATH="/usr/local/share/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Boost
export BOOST_ROOT="/usr/local"
''
