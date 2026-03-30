# Cross-compiled Nix for s390x (IBM Z).
#
# Uses the modular nixpkgs nix package's overrideSource/appendPatches API
# to swap in our pinned source (2.35.0 from master) and apply s390x patches.
#
# nixpkgs handles all dependencies (boost, curl, sqlite, libgit2, libseccomp,
# blake3, etc.) automatically via pkgsCross.s390x.
{ pkgsCross, sources }:

let
  # Use nixVersions.latest as the base — closest released version to our
  # 2.35.0 master source. The modular build system handles the source swap.
  base = pkgsCross.nixVersions.latest;
in
(base.overrideSource sources.nix.src).appendPatches sources.patches
