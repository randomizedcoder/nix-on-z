# Ubuntu on Z: Defaults That Need Fixing

[Back to overview](../S390X-PORTING-GUIDE.md)

---

Ubuntu's default server install ships with services and settings designed for
desktop and laptop hardware. On an IBM Z (s390x) build server — especially a
resource-constrained LinuxONE Community Cloud instance (2 vCPU, 4GB RAM) — many
of these waste CPU, memory, and I/O that should go to compilation.

This document explains what to change and **why**. The automated fix is:

```bash
nix run .#tune-ubuntu   # SSHs to z and applies all fixes
```

The implementation lives in `nix/z-tuning/` — one file per concern, each with
detailed comments explaining the reasoning. This document provides the broader
context.

## Services to Disable

### Hardware that doesn't exist on Z

These services manage hardware that IBM Z physically does not have:

| Service | What it does | Why Z doesn't have it |
|---------|-------------|----------------------|
| **ModemManager** | Manages 3G/4G/5G modems and SMS | No USB, no PCIe slots, no cellular hardware |
| **udisks2** | Desktop disk management (automount, eject, SMART) | No removable media, no desktop |
| **getty@tty1** | Virtual console login on tty1 | No physical display — access via SSH or Z serial consoles (hvc0, ttysclp0) |

### Services replaced by Nix

| Service | What it does | Why we don't need it |
|---------|-------------|---------------------|
| **snapd** | Canonical's snap package manager | We use Nix for all software management. snapd runs a permanent daemon (~40MB RSS), polls for updates, mounts squashfs images. All unnecessary when Nix handles everything |
| **PackageKit** | D-Bus abstraction for GUI package tools | GNOME Software and KDE Discover use PackageKit. There is no GUI on Z — we manage packages via Nix and occasionally `apt` over SSH |

### Services unnecessary on a build VM

| Service | What it does | Why disable on a build VM |
|---------|-------------|--------------------------|
| **Open vSwitch** | Software-defined networking (SDN) virtual switch | Ubuntu on Z includes OVS because mainframes commonly run many VMs with complex virtual networking (z/VM guest LANs, VSWITCH). On a single-purpose build VM with one network interface, OVS's two daemons (ovsdb-server + ovs-vswitchd, both with `mlockall`) waste locked memory. Re-enable if you later need multi-VM test networking |
| **multipathd** | Multipath SAN storage failover | Z systems often use FCP (Fibre Channel) SAN with multiple physical paths. multipathd manages failover and load-balancing between paths. LinuxONE Community Cloud VMs use single-path virtio-blk — there's only one path, nothing to manage |
| **irqbalance** | Distributes hardware interrupts across CPUs | On a 2-vCPU VM, irqbalance has almost nothing to balance. Wakes up every 10 seconds to re-evaluate for no benefit. Keep enabled on larger systems (8+ vCPUs) with many I/O devices |
| **networkd-dispatcher** | Python daemon reacting to network state changes | Runs permanently (~30MB RSS) waiting for interface up/down events. On Z, the network configuration is static — the interface comes up at boot and stays up. No WiFi roaming, no cable plug/unplug |

### Tradeoff: unattended-upgrades

**unattended-upgrades** performs automatic Ubuntu security patching. This is a
genuine tradeoff:

| Reason to disable | Reason to keep |
|-------------------|---------------|
| Runs a permanent Python process (~30MB RSS) | Applies kernel and OpenSSH security patches |
| Can install packages mid-build, causing subtle breakage | Community Cloud VMs are internet-facing |
| Can trigger dpkg locks blocking manual apt | If you forget to patch, you're running vulnerable sshd |
| On a Nix-managed system, apt packages matter less | |

**Our decision:** Disable on build servers where builds run for hours and
interruption is costly. Schedule manual updates during maintenance windows:
```bash
sudo apt update && sudo apt upgrade
```

### What to keep

Don't disable these — they're actually useful on Z:

| Service | Why keep it |
|---------|------------|
| `systemd-journald` | Log collection — essential for debugging build failures |
| `systemd-networkd` | Network configuration — your only connectivity |
| `systemd-resolved` | DNS resolution — needed for nix fetching sources |
| `systemd-timesyncd` | Clock sync — build timestamps and TLS certificate validation need correct time |
| `sshd` | Remote access — your only way in |
| `cron` | Scheduled tasks (manual patching, log rotation) |
| `dbus` | IPC bus — systemd depends on it |
| `rsyslog` | Syslog — complementary to journald |
| `iucvserd` | Z-specific inter-VM communication (IUCV) — the hypervisor uses this |
| `auditd` | Security audit — keep unless pure throwaway VM |
| `polkit` | Authorization framework — needed by systemd for `sudo systemctl` etc. |

### Estimated savings

On a 2-vCPU / 4GB system, disabling the above frees:

| Resource | Before | After | Freed |
|----------|--------|-------|-------|
| Resident memory | ~300-500MB | ~100-150MB | **~200-350MB** |
| Running processes | ~35+ | ~20 | 15+ fewer context switches |
| Python interpreters | 2 (networkd-dispatcher, unattended-upgrades) | 0 | ~60MB RSS total |
| Daemons polling/waking | 6+ | 1-2 | Less CPU wake-up overhead |

On a 4GB build server, 200-350MB freed is the difference between the ClickHouse
linker OOM-killing and succeeding.

## Serial Consoles

Ubuntu on Z starts three serial getty processes:

```
serial-getty@ttyS0.service     # standard serial port
serial-getty@ttysclp0.service  # SCLP console (Z-specific hardware console)
serial-getty@hvc0.service      # virtio console (KVM/LPAR hypervisor console)
```

You probably only need one. On LinuxONE Community Cloud, `hvc0` or `ttysclp0` is
the active console. The others can be disabled:

```bash
# Check which console you're using (SSH shows /dev/pts/0, not the console):
cat /sys/class/tty/console/active

# Disable unused serial consoles (keep hvc0 for Community Cloud):
sudo systemctl disable --now serial-getty@ttyS0.service
sudo systemctl disable --now serial-getty@ttysclp0.service
```

## Sysctl Tuning

All sysctl settings are in one file: `nix/z-tuning/sysctl.nix`. The automated
tool writes them to `/etc/sysctl.d/99-nix-on-z.conf`. Three sections:

### 1. Memory / VM tuning

Ubuntu's defaults are conservative — designed for generic servers that balance
many workloads. A build server doing heavy compilation has different priorities:
keep compiler processes in RAM, batch disk writes, cache the /nix/store tree.

| Sysctl | Default | Our value | Why |
|--------|---------|-----------|-----|
| `vm.swappiness` | 60 | **10** | Prefer dropping file cache over swapping out compiler processes. Set to 10, not 0, so swap is still used under real memory pressure |
| `vm.dirty_ratio` | 10 | **40** | Don't force disk sync until 40% of RAM is dirty pages. Prevents compiler stalls waiting for writeback during heavy object file generation |
| `vm.dirty_background_ratio` | 5 | **10** | Start background writeback at 10%. Lets the kernel batch writes instead of flushing tiny amounts constantly |
| `vm.vfs_cache_pressure` | 100 | **50** | Keep directory/inode caches longer. Nix builds traverse deep paths in /nix/store — thousands of symlinks and directory lookups. Reducing cache pressure avoids repeated `stat()` and `readdir()` syscalls |
| `fs.file-max` | 65536 | **1048576** | Large nix builds open thousands of files simultaneously (source, objects, libraries, store symlinks) |
| `fs.inotify.max_user_watches` | 8192 | **524288** | Some build tools use inotify for file watching |

### 2. Network tuning

Z build servers are accessed exclusively via SSH. Long-lived sessions, rsync
transfers of nixpkgs (~2GB), and `nix copy` operations benefit from these:

| Sysctl | Default | Our value | Why |
|--------|---------|-----------|-----|
| `tcp_keepalive_time` | 7200 (2 hours!) | **120** | Detect dead SSH sessions in ~4 minutes instead of ~11 minutes. Z cloud sessions can silently disconnect |
| `tcp_keepalive_intvl` | 75 | **30** | After keepalive_time, probe every 30s |
| `tcp_keepalive_probes` | 9 | **4** | Give up after 4 probes (120 + 30×4 = 240s total) |
| `tcp_rmem` / `tcp_wmem` | ~212KB | **1-16MB** | Larger buffers for rsync bulk transfers. Default 212KB bottlenecks large file copies |
| `core.rmem_max` / `wmem_max` | 212KB | **25MB** | Allow applications to request large socket buffers |
| `tcp_slow_start_after_idle` | 1 | **0** | SSH sessions idle between commands — without this, every command after a pause restarts with a tiny congestion window |
| `tcp_fastopen` | 0 | **3** | Save one RTT on reconnections (client + server). Useful for repeated SSH/rsync |
| `tcp_fin_timeout` | 60 | **30** | Free TIME-WAIT sockets faster for repeated connections |
| `tcp_tw_reuse` | 0 | **1** | Allow reuse of TIME-WAIT sockets |
| `ip_local_port_range` | 32768-60999 | **1026-65535** | More ephemeral ports for parallel nix fetches |
| `tcp_rto_min_us` | 200000 | **50000** | Lower minimum retransmission timeout. Z cloud networking has reasonable latency; 200ms floor adds unnecessary delay |
| `tcp_notsent_lowat` | MAX_INT | **131072** | Notify writer sooner when buffer space is available. Makes interactive SSH feel snappier by reducing bufferbloat |

### 3. s390x-specific kernel tunables

These sysctls **only exist on IBM Z** — they control hypervisor interaction and
Z-specific kernel behavior.

#### `kernel.spin_retry` (s390x only)

Controls how many times the kernel spins on a contended lock before yielding the
vCPU to the z/VM hypervisor via the `DIAGNOSE 0x44` instruction.

- **Default:** 1000
- **Our setting:** default (1000) — appropriate for LinuxONE Community Cloud
- **When to change:** On heavily overcommitted z/VM guests (CPU steal > 20%),
  raise to 2000-5000. This avoids expensive hypervisor intercepts for short
  critical sections. On dedicated LPARs, the default is fine — the CPU is never
  stolen.

#### Transparent Hugepages (THP)

**Important s390x difference:** Hugepages on s390x are **1MB** (not 2MB like
x86_64). This means aggressive THP allocation wastes more memory per page.

| Architecture | Normal page | Hugepage |
|-------------|------------|----------|
| x86_64 | 4 KB | 2 MB |
| aarch64 | 4 KB | 2 MB |
| **s390x** | 4 KB | **1 MB** |

We set THP to `madvise` (via sysfs, not sysctl):
```bash
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag
```

This lets applications that know they benefit (JVM, ClickHouse at runtime) opt
in with `madvise(MADV_HUGEPAGE)`, while builds use normal 4KB pages. With only
4GB RAM, we can't afford THP aggressively allocating 1MB pages for every
compiler process.

**Static hugepages:** Don't allocate them on a 4GB build VM. There's not enough
RAM to lock any meaningful amount away from the compiler.

#### CMM (Cooperative Memory Management) — z/VM only

The `cmm` kernel module allows Linux to voluntarily return memory to the z/VM
hypervisor so it can redistribute to other guests. Controlled via:

- `vm.cmm_pages` — pages permanently loaned to z/VM
- `vm.cmm_timed_pages` — pages temporarily loaned with expiry
- `vm.cmm_timeout` — timeout for timed pages

On LinuxONE Community Cloud, the z/VM Resource Manager (VMRM) typically manages
CMM automatically. We leave these at defaults (0) — on a build server we want
all our RAM, not volunteering it to the hypervisor.

#### `kernel.userprocess_debug` (s390x only)

Controls whether unhandled signals (SIGSEGV, etc.) log a backtrace including the
s390x PSW (Program Status Word) and registers. Default: 1 (enabled). Leave it on
during development — useful for debugging build crashes.

#### Entropy / Hardware RNG

s390x has a true hardware random number generator (TRNG) via the CPACF `PRNO`
instruction. The `s390_trng` kernel module feeds it to `/dev/hwrng`. If builds
stall waiting for entropy (unlikely but possible during key generation):

```bash
# Verify hardware RNG is active:
cat /sys/devices/virtual/misc/hw_random/rng_current
# Should show: s390-trng

# Check entropy pool:
cat /proc/sys/kernel/random/entropy_avail
# Should be near 4096 with CPACF TRNG
```

#### Boot parameters

For z/VM guests, consider adding to the kernel command line (parmfile or zipl):

- `cmma=on` — Enables CMMA (Collaborative Memory Management Assist). Uses the
  `ESSA` instruction to mark pages as stable/volatile/unused, letting z/VM make
  smarter paging decisions. Reduces unnecessary I/O for file cache pages.
  **Recommended on z/VM guests** where memory is overcommitted.

## Swap

With only 4GB RAM, ClickHouse linking **will** OOM without swap.

```bash
# Create 4GB swap file (matches RAM size)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

**Why 4GB?** ClickHouse's `lld` linker can use 6-8GB for the final binary. With
4GB RAM + 4GB swap = 8GB total, linking should survive. It will be slow (swap
thrashing on virtio-blk), but it will complete.

## Nix Build User Limits

The nix daemon runs builds as `nixbld` users. Default ulimits are too low for
large builds that open thousands of files:

```bash
cat <<'EOF' | sudo tee /etc/security/limits.d/99-nix-build.conf
nixbld  soft  nofile  1048576
nixbld  hard  nofile  1048576
nixbld  soft  nproc   unlimited
nixbld  hard  nproc   unlimited
EOF
```

## DASD Tuning (if applicable)

If your Z system uses DASD (Direct Access Storage Device) instead of virtio-blk:

```bash
# Increase read-ahead for Nix store traversal (largely sequential I/O):
for dev in /sys/block/dasd*/queue/read_ahead_kb; do
    echo 2048 > "$dev"
done

# On z/VM: enable DIAG I/O for better throughput (device must be offline first):
echo 0 > /sys/bus/ccw/devices/0.0.0150/online
echo 1 > /sys/bus/ccw/devices/0.0.0150/use_diag
echo 1 > /sys/bus/ccw/devices/0.0.0150/online
```

LinuxONE Community Cloud uses virtio-blk, not DASD, so these don't apply there.

## Pre-Build Garbage Collection

**This saved our ClickHouse build from running out of disk.**

When iterating on s390x fixes — trying a build, hitting an error, patching,
rebuilding — each failed attempt leaves behind partial store paths. On a 50GB
disk these accumulate silently. We discovered **5.7GB of dead paths** from just
a few iterations of fixing OpenSSL, PCRE2, and bison:

```
$ nix-collect-garbage --dry-run
2844 store paths would be deleted

$ nix-collect-garbage
2844 store paths deleted, 5.7 GiB freed

$ df -h /
/dev/dasda1   50G   33G   15G  70%  /    # was 85% before GC
```

Without this cleanup, the ClickHouse build (which needs 5-10GB of build
artifacts on top of the existing 15-20GB nix store) would have run out of
disk mid-compilation.

**Safety:** `nix-collect-garbage` only removes paths with no GC roots — it will
not touch anything referenced by a running build, current profiles, or `result`
symlinks. It's safe to run even while a build is in progress.

The `tune-ubuntu` app runs this as its final step, after all service disables
and sysctl tuning. This ensures maximum disk headroom before kicking off a
long build.

**Recommendation:** Always run `nix run .#tune-ubuntu` (or at minimum
`nix-collect-garbage`) before starting a multi-hour build on a
resource-constrained VM.

## Automated Tool

All of the above is implemented as modular Nix derivations in `nix/z-tuning/`:

```
nix/z-tuning/
├── default.nix                      # combines all modules into one app
├── disable-modemmanager.nix         # no modem hardware on Z
├── disable-snapd.nix               # we use Nix, not snap
├── disable-packagekit.nix           # no GUI on Z
├── disable-udisks2.nix             # no removable media on Z
├── disable-unattended-upgrades.nix  # can interrupt builds (see tradeoff)
├── disable-openvswitch.nix          # not needed on single build VMs
├── disable-multipathd.nix           # Community Cloud uses single-path
├── disable-irqbalance.nix           # negligible on 2-vCPU
├── disable-networkd-dispatcher.nix  # static network, no events
├── disable-getty-tty1.nix           # no physical display
├── disable-motd-news.nix           # wget to Canonical on every login
├── sysctl.nix                       # memory, network, and s390x-specific
├── swap.nix                         # 4GB swap for linker survival
├── nix-limits.nix                   # nix build user file/process limits
└── pre-build-gc.nix                 # garbage collect dead store paths
```

Each file has detailed comments explaining the reasoning. To apply:

```bash
nix run .#tune-ubuntu              # uses Z_HOST=z by default
Z_HOST=myhost nix run .#tune-ubuntu  # target a different host
```

---

*Part of the [nix-on-z](https://github.com/) project. Last updated: 2026-03-31.*
