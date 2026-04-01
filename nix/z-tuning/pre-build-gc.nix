# Pre-build garbage collection — clean up dead store paths before a long build.
#
# WHY: When iterating on fixes (OpenSSL, PCRE2, bison, etc.), each failed
# build leaves behind partial store paths. On a 50GB disk these accumulate
# fast — we found 5.7GB of dead paths from just a few iterations.
#
# Running GC before a big build ensures maximum disk headroom. This is
# especially important for ClickHouse, which needs 5-10GB for build artifacts
# plus the existing 15-20GB nix store.
#
# SAFETY: nix-collect-garbage only removes paths with no GC roots. It will
# not touch anything referenced by the current build, profiles, or result
# symlinks. Safe to run even if a build is in progress.
{
  name = "pre-build-gc";
  description = "Garbage collect dead nix store paths before building";
  script = ''
    echo "--- Pre-build nix garbage collection ---"
    echo "Disk before:"
    df -h / | tail -1

    DEAD_COUNT=$(nix-collect-garbage --dry-run 2>&1 | grep -oP '\d+ store paths' | grep -oP '\d+')
    if [ "''${DEAD_COUNT:-0}" -gt 0 ]; then
      echo "  $DEAD_COUNT dead store paths found, collecting..."
      nix-collect-garbage 2>&1 | tail -1
    else
      echo "  no dead store paths"
    fi

    echo "Disk after:"
    df -h / | tail -1
  '';
}
