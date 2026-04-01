# snapd — Canonical's snap package manager daemon.
#
# WHY DISABLE: We use Nix for package management. snapd runs a permanent
# daemon (~40MB RSS), polls Canonical's servers for updates, mounts squashfs
# images, and manages its own confinement. All of this is unnecessary overhead
# when Nix handles all software installation.
#
# snapd also consumes disk space for its snapshots and revision tracking.
# On a 33GB disk, this matters.
{
  name = "disable-snapd";
  description = "snapd — we use Nix, not snap, for package management";
  script = ''
    disable_service snapd.service
    disable_service snapd.socket
    disable_service snapd.seeded.service
  '';
}
