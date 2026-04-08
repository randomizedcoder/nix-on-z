# unattended-upgrades — automatic Ubuntu security patching.
#
# TRADEOFF: This is a judgement call, not an obvious disable.
#
# REASONS TO DISABLE:
#   - Runs a permanent Python process (~30MB RSS) waiting for shutdown signal
#   - Can install packages mid-build, causing subtle breakage (e.g., libc
#     upgraded while GCC is linking against the old one)
#   - Can trigger dpkg locks that block manual apt operations
#   - On a Nix-managed system, Ubuntu's apt packages matter less — we build
#     everything from source via Nix
#
# REASONS TO KEEP:
#   - Applies kernel and OpenSSH security patches automatically
#   - LinuxONE Community Cloud VMs are internet-facing
#   - If you forget to manually patch, you're running known-vulnerable sshd
#
# DECISION: Disable for build servers where builds run for hours and
# interruption is costly. If this is a long-lived VM, schedule manual
# updates during maintenance windows instead:
#   sudo apt update && sudo apt upgrade
{
  name = "disable-unattended-upgrades";
  description = "unattended-upgrades — can interrupt long builds (see tradeoff notes)";
  script = ''
    disable_service unattended-upgrades.service
    echo "  NOTE: Remember to manually run 'apt update && apt upgrade' periodically"
  '';
}
