# Flake checks: patch application verification.
# Per-script shellcheck checks are provided by zScripts.checks (wired in flake.nix).
{ pkgs, sources, self }:

{
  patches-apply = pkgs.stdenvNoCC.mkDerivation {
    name = "verify-patches-apply";
    src = sources.nix.src;
    patches = sources.patches;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      echo "All ${toString (builtins.length sources.patches)} patches applied cleanly."
      touch $out
    '';
  };
}
