# nixpkgs overlay for s390x cross-compilation fixes.
#
# These are candidates for upstream nixpkgs submission — see
# nixpkgs-patches/ for individual patch files.
final: prev:

let
  inherit (final) lib;
  isS390xCross = final.stdenv.hostPlatform.isS390x
    && final.stdenv.hostPlatform != final.stdenv.buildPlatform;
in
{
  # --- Fix: OpenSSL s390x cross-compilation target ---
  #
  # Without this, cross-compiling OpenSSL for s390x falls through to
  # "linux-generic64" which misses s390x-specific CPACF hardware crypto
  # acceleration (AES, SHA, etc. in hardware).
  #
  # OpenSSL has a dedicated "linux64-s390x" target that enables:
  #   - CPACF instruction support (hardware AES, SHA, GHASH)
  #   - s390x assembly optimizations (keccak1600, poly1305, etc.)
  #   - Proper 64-bit s390x calling convention
  openssl = prev.openssl.overrideAttrs (old: lib.optionalAttrs isS390xCross {
    configureScript = "./Configure linux64-s390x";
  });
}
