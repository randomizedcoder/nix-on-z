# Sysctl tuning for s390x build servers.
#
# Three sections:
#   1. Memory/VM — prioritize compilation over cache, handle 4GB RAM constraint
#   2. Network — faster dead-connection detection, larger buffers for rsync/SSH
#   3. s390x-specific — kernel tunables that only exist on IBM Z
{
  name = "sysctl";
  description = "Memory, network, and s390x-specific kernel tuning";
  script = ''
    echo "--- Applying sysctl tuning ---"
    cat > /etc/sysctl.d/99-nix-on-z.conf <<'SYSCTL'
# =============================================================================
# nix-on-z sysctl tuning for s390x build servers
# See: docs/ubuntu-z-tuning.md
# =============================================================================

# -----------------------------------------------------------------------------
# 1. MEMORY / VM
# Ubuntu defaults are conservative for general servers. A build server doing
# heavy compilation (GCC, LLVM, ClickHouse) benefits from these changes.
# -----------------------------------------------------------------------------

# Prefer dropping file cache over swapping out build processes.
# Default: 60. On a 4GB build VM, we want compiler processes to stay in RAM
# even if it means re-reading source files from disk.
vm.swappiness = 10

# Allow more dirty pages before forcing writeback to disk.
# Default: dirty_ratio=10, dirty_background_ratio=5.
# Higher values let builds batch I/O writes instead of stalling mid-compile
# to flush pages. Background writeback starts at 10%, forced sync at 40%.
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# Keep directory/inode caches longer.
# Default: 100 (equal pressure on VFS cache vs page cache).
# Nix builds traverse huge directory trees in /nix/store — thousands of
# symlinks and deep paths. Keeping VFS cache warm avoids repeated readdir
# and stat syscalls. 50 = half the reclaim pressure on dentries/inodes.
vm.vfs_cache_pressure = 50

# Nix builds open many files simultaneously — source files, object files,
# libraries, /nix/store symlinks. Default limits are too low for parallel
# builds of large packages like LLVM or ClickHouse.
fs.file-max = 1048576
fs.inotify.max_user_watches = 524288

# -----------------------------------------------------------------------------
# 2. NETWORK
# Z build servers are accessed exclusively via SSH. Long-lived sessions,
# rsync transfers, and nix remote builds benefit from these settings.
# Adapted from a production NixOS desktop configuration.
# -----------------------------------------------------------------------------

# Detect dead SSH sessions in ~2 minutes instead of ~11 minutes.
# Default: time=7200 (2 hours!), intvl=75, probes=9 → 11+ minutes.
# Z cloud sessions can silently disconnect. Fast detection prevents
# hung tmux sessions and stale nix-build connections.
# 120s + (30s × 4 probes) = 240s = 4 minutes to detect dead peer.
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 4

# Larger TCP buffers for rsync and nix copy operations.
# Default: rmem/wmem ~212KB. Raised to 25MB for bulk transfers.
# rsync of nixpkgs (~2GB) and nix copy of store paths benefit from
# not being bottlenecked by small socket buffers.
net.core.rmem_default = 26214400
net.core.rmem_max = 26214400
net.core.wmem_default = 26214400
net.core.wmem_max = 26214400
net.ipv4.tcp_rmem = 4096 1000000 16000000
net.ipv4.tcp_wmem = 4096 1000000 16000000

# Don't restart TCP slow start after idle periods.
# Default: 1 (enabled). SSH sessions idle between commands — without this,
# every new command after a pause starts with a tiny congestion window,
# making the first rsync chunk slow.
net.ipv4.tcp_slow_start_after_idle = 0

# Enable TCP Fast Open (both client and server).
# Saves one RTT on reconnections — useful for repeated SSH/rsync to Z.
net.ipv4.tcp_fastopen = 3

# Standard TCP optimizations (should already be on, but ensure).
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1

# Reduce TIME-WAIT socket timeout (30s vs default 60s).
# Frees up sockets faster for repeated rsync/SSH connections.
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1

# Wider ephemeral port range — more concurrent connections.
# Default: 32768-60999. Useful when running many parallel nix fetches.
net.ipv4.ip_local_port_range = 1026 65535

# Lower minimum RTO (50ms vs 200ms default).
# Z cloud networking has reasonable latency; 200ms floor is too conservative
# and adds unnecessary delay on retransmits.
net.ipv4.tcp_rto_min_us = 50000

# Notify writer sooner when socket buffer space is available.
# Reduces bufferbloat on interactive SSH sessions — typing feels snappier.
# Default: MAX_INT (disabled). 128KB is a good balance.
net.ipv4.tcp_notsent_lowat = 131072

# Reflect TOS/DSCP markings on reply packets.
net.ipv4.tcp_reflect_tos = 1

# -----------------------------------------------------------------------------
# 3. s390x-SPECIFIC
# These sysctls only exist on IBM Z hardware. They control hypervisor
# interaction and Z-specific kernel behavior.
# -----------------------------------------------------------------------------

# spin_retry: How many times to spin on a contended lock before yielding
# the vCPU to the z/VM hypervisor (via DIAGNOSE 0x44 instruction).
# Default: 1000. On a dedicated LPAR or lightly loaded z/VM, default is fine.
# On overcommitted z/VM (CPU steal > 20%), raise to 2000-5000 to avoid
# expensive hypervisor intercepts for short critical sections.
# LinuxONE Community Cloud is lightly loaded — keep default.
# kernel.spin_retry = 1000

SYSCTL

    # Transparent Hugepages: set to madvise (not a sysctl — done via sysfs).
    # s390x hugepages are 1MB (not 2MB like x86). With only 4GB RAM, we don't
    # want THP aggressively allocating 1MB pages for every malloc. madvise lets
    # the JVM and linker explicitly request them while builds use normal 4KB pages.
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
      echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
      echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag
      echo "  THP set to madvise (s390x hugepages are 1MB, not 2MB)"
    fi

    sysctl --system >/dev/null
    echo "  applied /etc/sysctl.d/99-nix-on-z.conf"
  '';
}
