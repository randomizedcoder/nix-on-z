# Deployment scripts as writeShellApplication (gets shellcheck for free).
#
# sync         — rsync patched source bundle to z
# build-remote — SSH to z and run build scripts
# test-remote  — SSH to z and run test suite
{ pkgs, self }:

let
  system = "x86_64-linux";
  bundle = self.packages.${system}.source-bundle;
in
{
  sync = {
    type = "app";
    program = "${pkgs.writeShellApplication {
      name = "nix-on-z-sync";
      runtimeInputs = [ pkgs.rsync pkgs.openssh ];
      text = ''
        Z_HOST="''${Z_HOST:-z}"
        echo "Syncing patched nix source to $Z_HOST..."
        rsync -avz --delete \
          --exclude='/build/' --exclude='/builddir/' \
          "${bundle}/nix-source/" "$Z_HOST:nix/"
        rsync -avz --delete \
          --exclude='/build/' \
          "${bundle}/rapidcheck-source/" "$Z_HOST:rapidcheck/"
        rsync -avz "${bundle}/scripts/" "$Z_HOST:nix-on-z/"
        rsync -avz "${bundle}/patches/" "$Z_HOST:nix-on-z/patches/"
        echo "Sync complete. ssh $Z_HOST and run scripts in ~/nix-on-z/"
      '';
    }}/bin/nix-on-z-sync";
  };

  build-remote = {
    type = "app";
    program = "${pkgs.writeShellApplication {
      name = "nix-on-z-build-remote";
      runtimeInputs = [ pkgs.openssh ];
      text = ''
        Z_HOST="''${Z_HOST:-z}"
        echo "Running build on $Z_HOST..."
        ssh "$Z_HOST" 'cd ~/nix-on-z && for s in 00-apt-deps.sh 01-meson-pip.sh 02-gcc14.sh 03-env.sh 04-boost.sh 05-nlohmann-json.sh 06-toml11.sh 07-sqlite.sh 08-boehm-gc.sh 09-curl.sh 10-libgit2.sh 11-libseccomp.sh 12-blake3.sh 13-nix-build.sh 14-nix-install.sh; do echo "=== $s ==="; bash "$s" || exit 1; done'
        echo "Build complete."
      '';
    }}/bin/nix-on-z-build-remote";
  };

  test-remote = {
    type = "app";
    program = "${pkgs.writeShellApplication {
      name = "nix-on-z-test-remote";
      runtimeInputs = [ pkgs.openssh ];
      text = ''
        Z_HOST="''${Z_HOST:-z}"
        echo "Running tests on $Z_HOST..."
        ssh "$Z_HOST" 'cd ~/nix-on-z && bash 15-test-deps.sh && bash 16-nix-build-tests.sh && bash 17-run-tests.sh'
        echo "Tests complete."
      '';
    }}/bin/nix-on-z-test-remote";
  };
}
