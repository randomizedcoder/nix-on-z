# Cross-compiled Nix for s390x (IBM Z).
#
# Uses the modular nixpkgs nix package's overrideSource/appendPatches API
# to swap in our pinned source (2.35.0 from master) and apply s390x patches.
#
# nixpkgs handles all dependencies (boost, curl, sqlite, libgit2, libseccomp,
# blake3, etc.) automatically via the s390x cross-compilation toolchain.
#
# The cross toolchain uses gcc.arch=z13 (set in flake.nix crossSystem) which
# enables vector extensions and sets the minimum architecture level. This
# fixes assembly failures in OpenSSL, enables hardware CRC32 in zlib, etc.
#
# Key override: sandbox-shell uses /usr/bin/bash-static instead of busybox.
# musl (which busybox requires) doesn't support s390x's IEEE 128-bit long
# doubles, so the busybox-sandbox-shell build fails. Using bash-static
# matches what the native build scripts already do.
{ pkgs, pkgsCross, sources }:

let
  # Use nixVersions.latest as the base — closest released version to our
  # 2.35.0 master source. The modular build system handles the source swap.
  base = pkgsCross.nixVersions.latest;

  # Fake busybox-sandbox-shell that symlinks to /usr/bin/bash-static.
  # musl doesn't support s390x's IEEE 128-bit long doubles, so the real
  # busybox-sandbox-shell can't be cross-compiled. This derivation is
  # trivial — just a symlink — and must be deployed alongside the nix binary.
  sandboxShell = pkgs.runCommand "sandbox-shell-s390x" {} ''
    mkdir -p $out/bin
    ln -s /usr/bin/bash-static $out/bin/busybox
  '';
in
((base.overrideSource sources.nix.src).appendPatches sources.patches)
  .overrideScope (finalScope: prevScope: {
    nix-store = prevScope.nix-store.override {
      busybox-sandbox-shell = sandboxShell;
    };
  })
