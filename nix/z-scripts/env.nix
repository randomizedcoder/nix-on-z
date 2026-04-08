# Shared environment setup for s390x bootstrap scripts.
# Replaces 03-env.sh — interpolated into every script with needsEnv = true,
# and also emitted as a standalone 03-env.sh for interactive use on z.
''
# GCC 14
export CC=/usr/local/bin/gcc
export CXX=/usr/local/bin/g++

# Auto-detect s390x architecture level from /proc/cpuinfo and set -march accordingly.
# This ensures binaries use the best instructions for the hardware:
#   z13 (2964/2965) — VXE (vector extensions)
#   z14 (3906/3907) — VXE2
#   z15 (8561/8562) — VXE3, DFLTCC (hardware deflate), CPACF
#   z16 (3931/3932) — NNPA (AI accelerator)
# If detection fails, falls back to z13 (safe for all modern Z hardware).
# Users can override by setting S390X_MARCH before sourcing this file.
if [[ -z "''${S390X_MARCH:-}" ]]; then
  _MACHINE_TYPE=$(grep -m1 "^processor.*machine" /proc/cpuinfo 2>/dev/null | awk '{print $NF}')
  case "''${_MACHINE_TYPE:-}" in
    2964|2965) S390X_MARCH="z13" ;;
    3906|3907) S390X_MARCH="z14" ;;
    8561|8562) S390X_MARCH="z15" ;;
    3931|3932) S390X_MARCH="z16" ;;
    9175)      S390X_MARCH="arch15" ;;
    *)         S390X_MARCH="z13" ;;
  esac
  echo "Detected s390x architecture: -march=''${S390X_MARCH} (machine type ''${_MACHINE_TYPE:-unknown})"
fi
export CFLAGS="''${CFLAGS:+$CFLAGS }-march=''${S390X_MARCH}"
export CXXFLAGS="''${CXXFLAGS:+$CXXFLAGS }-march=''${S390X_MARCH}"

# Binaries
export PATH="''${HOME}/.local/bin:/usr/local/bin:''${PATH}"

# Libraries built from source
export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# pkg-config (include /usr/local/share/pkgconfig for nlohmann_json)
export PKG_CONFIG_PATH="/usr/local/share/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Boost
export BOOST_ROOT="/usr/local"
''
