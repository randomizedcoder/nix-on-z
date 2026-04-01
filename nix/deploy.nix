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

  check-arch = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-check-arch";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Checking s390x hardware on $Z_HOST..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" 'bash -s' <<'REMOTE_SCRIPT'

      CURRENT_ARCH="''${1:-z13}"

      if [[ ! -f /proc/cpuinfo ]]; then
        echo "ERROR: /proc/cpuinfo not found. Are you running on s390x?"
        exit 1
      fi

      MACHINE_TYPE=$(grep -m1 "^processor.*machine" /proc/cpuinfo | awk "{print \$NF}")
      FEATURES=$(grep "^features" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
      CPUS=$(grep "^# processors" /proc/cpuinfo | awk "{print \$NF}")

      echo "=== IBM Z Hardware Detection ==="
      echo "Machine type:    $MACHINE_TYPE"
      echo "Processors:      ''${CPUS:-unknown}"
      echo "CPU features:    $FEATURES"
      echo ""

      # Machine type -> gcc -march mapping
      # See: https://gcc.gnu.org/onlinedocs/gcc/S_002f390-and-zSeries-Options.html
      case "$MACHINE_TYPE" in
        2964|2965) DETECTED_ARCH="z13";   YEAR="2015"; HW_FEATURES="VXE (vector extensions)" ;;
        3906|3907) DETECTED_ARCH="z14";   YEAR="2017"; HW_FEATURES="VXE2, misc-insn-ext-2" ;;
        8561|8562) DETECTED_ARCH="z15";   YEAR="2019"; HW_FEATURES="VXE3, DFLTCC (hardware deflate), sort" ;;
        3931|3932) DETECTED_ARCH="z16";   YEAR="2022"; HW_FEATURES="NNPA (AI accelerator), bear-enh-1" ;;
        9175)      DETECTED_ARCH="arch15"; YEAR="2025"; HW_FEATURES="z17 features (requires GCC 15+)" ;;
        *)         echo "WARNING: Unknown machine type $MACHINE_TYPE"; exit 1 ;;
      esac

      # Arch level ordering for comparison
      arch_level() {
        case "$1" in
          z13) echo 5 ;; z14) echo 6 ;; z15) echo 7 ;;
          z16) echo 8 ;; arch15) echo 9 ;; *) echo 0 ;;
        esac
      }

      echo "Detected:        $DETECTED_ARCH ($YEAR) — $HW_FEATURES"
      echo "Configured:      gcc.arch = \"$CURRENT_ARCH\""
      echo ""

      DETECTED_LEVEL=$(arch_level "$DETECTED_ARCH")
      CURRENT_LEVEL=$(arch_level "$CURRENT_ARCH")

      if [[ "$DETECTED_LEVEL" -gt "$CURRENT_LEVEL" ]]; then
        echo ">>> RECOMMENDATION: Your hardware supports gcc.arch = \"$DETECTED_ARCH\""
        echo "    which is higher than the currently configured \"$CURRENT_ARCH\"."
        echo ""
        echo "    To optimize, edit lib/systems/examples.nix:"
        echo "      gcc.arch = \"$DETECTED_ARCH\";"
        echo ""
        echo "    This enables: $HW_FEATURES"
        if [[ "$DETECTED_LEVEL" -ge 7 ]] && [[ "$CURRENT_LEVEL" -lt 7 ]]; then
          echo ""
          echo "    NOTE: z15+ enables DFLTCC (hardware deflate) for zlib/gzip."
          echo "          10-50x faster compression with -march=z15."
        fi
      elif [[ "$DETECTED_LEVEL" -eq "$CURRENT_LEVEL" ]]; then
        echo "OK: gcc.arch = \"$CURRENT_ARCH\" matches your hardware."
      else
        echo "NOTE: gcc.arch = \"$CURRENT_ARCH\" targets newer hardware than detected."
        echo "      Binaries may not run correctly on this machine."
      fi
REMOTE_SCRIPT
    '';
  });

  tune-ubuntu = mkApp (import ./z-tuning { inherit pkgs; });

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
