{ pkgs }:

pkgs.mkShell {
  packages = with pkgs; [ rsync openssh shellcheck jq git ];
  shellHook = ''
    echo "nix-on-z dev shell"
    echo "  nix build .#nix-s390x     — cross-compile Nix for s390x"
    echo "  nix build .#source-bundle — prepare patched source"
    echo "  nix run .#sync            — rsync to z"
    echo "  nix run .#build-remote    — build on z via ssh"
    echo "  nix flake check           — shellcheck + patch verification"
  '';
}
