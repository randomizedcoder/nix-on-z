{
  description = "Nix 2.35.0 for s390x (IBM Z) with architecture patches";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";

      # Cross-compilation pkgs with s390x hardware optimization.
      # gcc.arch = "z13" enables vector extensions (SIMD) and sets the
      # minimum architecture level. z13 (2015) is the oldest IBM Z still
      # in production. This fixes cross-assembler failures (e.g., OpenSSL
      # s390x assembly uses z10+ instructions like cijne) and enables
      # hardware-accelerated CRC32 in zlib.
      pkgsCross = import nixpkgs {
        inherit system;
        crossSystem = {
          config = "s390x-unknown-linux-gnu";
          gcc = {
            arch = "z13";
          };
        };
        overlays = [ (import ./nix/s390x-overlay.nix) ];
      };

      # Native pkgs (x86_64) for build tools and non-cross packages
      pkgs = nixpkgs.legacyPackages.${system};
      sources = import ./nix/sources.nix { inherit (pkgs) fetchFromGitHub; };
      zScripts = import ./nix/z-scripts.nix { inherit pkgs; };
    in {
      packages.${system} = {
        nix-s390x = import ./nix/nix-s390x.nix {
          inherit pkgs sources pkgsCross;
        };
        source-bundle = import ./nix/source-bundle.nix {
          inherit pkgs sources self zScripts;
        };
      };

      apps.${system} = import ./nix/deploy.nix { inherit pkgs self zScripts; };

      devShells.${system}.default = import ./nix/devshell.nix { inherit pkgs; };

      checks.${system} = import ./nix/checks.nix { inherit pkgs sources self; }
        // zScripts.checks;
    };
}
