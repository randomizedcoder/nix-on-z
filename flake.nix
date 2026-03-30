{
  description = "Nix 2.35.0 for s390x (IBM Z) with architecture patches";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      sources = import ./nix/sources.nix { inherit (pkgs) fetchFromGitHub; };
    in {
      packages.${system} = {
        nix-s390x = import ./nix/nix-s390x.nix {
          inherit sources;
          pkgsCross = pkgs.pkgsCross.s390x;
        };
        source-bundle = import ./nix/source-bundle.nix {
          inherit pkgs sources self;
        };
      };

      apps.${system} = import ./nix/deploy.nix { inherit pkgs self; };

      devShells.${system}.default = import ./nix/devshell.nix { inherit pkgs; };

      checks.${system} = import ./nix/checks.nix { inherit pkgs sources self; };
    };
}
