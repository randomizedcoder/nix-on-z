# Ubuntu on Z tuning modules.
#
# Each module is a nix file returning { name, description, script }.
# This file combines them into a single writeShellApplication that
# SSHs to z and applies all fixes.
#
# Usage: nix run .#tune-ubuntu
# See:   docs/ubuntu-z-tuning.md
{ pkgs }:

let
  modules = [
    # Services to disable (one file per service/group)
    (import ./disable-modemmanager.nix)
    (import ./disable-snapd.nix)
    (import ./disable-packagekit.nix)
    (import ./disable-udisks2.nix)
    (import ./disable-unattended-upgrades.nix)
    (import ./disable-openvswitch.nix)
    (import ./disable-multipathd.nix)
    (import ./disable-irqbalance.nix)
    (import ./disable-networkd-dispatcher.nix)
    (import ./disable-getty-tty1.nix)
    (import ./disable-motd-news.nix)

    # System tuning
    (import ./sysctl.nix)
    (import ./swap.nix)
    (import ./nix-limits.nix)

    # Pre-build cleanup
    (import ./pre-build-gc.nix)
  ];

  # Combine all module scripts into one, with a header per module.
  combinedScript = builtins.concatStringsSep "\n" (map (m: ''
    echo ""
    echo "=== ${m.name}: ${m.description} ==="
    ${m.script}
  '') modules);

in pkgs.writeShellApplication {
  name = "nix-on-z-tune-ubuntu";
  runtimeInputs = [ pkgs.openssh ];
  text = ''
    Z_HOST="''${Z_HOST:-z}"
    echo "Tuning Ubuntu on $Z_HOST for s390x build workloads..."
    echo "Modules: ${toString (map (m: m.name) modules)}"
    # shellcheck disable=SC2029
    ssh -t "$Z_HOST" 'sudo bash -s' <<'REMOTE_SCRIPT'
    set -euo pipefail

    # Helper: disable a systemd service if it exists and is enabled
    disable_service() {
      local svc="$1"
      if systemctl is-enabled "$svc" &>/dev/null; then
        systemctl disable --now "$svc" 2>/dev/null && echo "  disabled: $svc" || echo "  skipped: $svc"
      else
        echo "  already disabled: $svc"
      fi
    }

    ${combinedScript}

    echo ""
    echo "=== Results ==="
    echo "Running services: $(systemctl list-units --type=service --state=running --no-legend | wc -l)"
    echo ""
    free -h
    echo ""
    swapon --show 2>/dev/null || echo "No swap configured"
    echo ""
    echo "Done. See docs/ubuntu-z-tuning.md for details."
    REMOTE_SCRIPT
  '';
}
