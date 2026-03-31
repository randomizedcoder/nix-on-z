# Deployment apps as writeShellApplication (gets shellcheck for free).
#
# sync            — rsync patched source bundle to z
# build-remote    — SSH to z and run build scripts
# test-remote     — SSH to z and run test suite
# verify-remote   — SSH to z and run environment verification
# fix-permissions — SSH to z and fix source tree permissions after meson install
{ pkgs, self, zScripts }:

let
  system = "x86_64-linux";
  bundle = self.packages.${system}.source-bundle;

  # Generate the 'for s in ...; do bash "$s"; done' command from script ordering
  mkRunCmd = order:
    let
      scripts = map (n: "${n}.sh") order;
    in
      "for s in ${builtins.concatStringsSep " " scripts}; do echo \"=== $s ===\"; bash \"$s\" || exit 1; done";

  mkApp = drv: {
    type = "app";
    program = "${drv}/bin/${drv.name}";
  };
in
{
  sync = mkApp (pkgs.writeShellApplication {
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
  });

  build-remote = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-build-remote";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Running build on $Z_HOST..."
      ssh "$Z_HOST" 'cd ~/nix-on-z && ${mkRunCmd zScripts.buildOrder}'
      echo "Build complete."
    '';
  });

  test-remote = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-test-remote";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Running tests on $Z_HOST..."
      ssh "$Z_HOST" 'cd ~/nix-on-z && ${mkRunCmd zScripts.testOrder}'
      echo "Tests complete."
    '';
  });

  verify-remote = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-verify-remote";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Running environment verification on $Z_HOST..."
      ssh "$Z_HOST" 'cd ~/nix-on-z && bash 18-verify-test-env.sh'
    '';
  });

  fix-permissions = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-fix-permissions";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      REMOTE_USER="''${REMOTE_USER:-$(ssh "$Z_HOST" whoami)}"
      echo "Fixing source tree permissions on $Z_HOST..."
      # meson install (via sudo) can leave files owned by root and read-only.
      # This restores user ownership and write permissions so subsequent
      # builds and tests can modify the source tree.
      ssh "$Z_HOST" "sudo chown -R $REMOTE_USER:$REMOTE_USER ~/nix && chmod -R u+w ~/nix"
      echo "Permissions fixed."
    '';
  });
}
