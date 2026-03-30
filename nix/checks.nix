# Flake checks: shellcheck on build scripts + patch application verification.
{ pkgs, sources, self }:

{
  shellcheck = pkgs.runCommand "shellcheck-scripts" {
    nativeBuildInputs = [ pkgs.shellcheck ];
    src = self;
  } ''
    cd "$src"
    echo "Running shellcheck on scripts/*.sh..."
    shellcheck --severity=warning --shell=bash scripts/*.sh
    echo "All scripts pass shellcheck."
    touch $out
  '';

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
