# Proposal: Expand Nix Binary Installer Platform Support

[Back to overview](../S390X-PORTING-GUIDE.md)

---

## Problem

The official Nix installer at `https://nixos.org/nix/install` supports 8
platforms. Nixpkgs defines 15 Linux platforms. 6 Linux platforms with real
hardware communities and active users have **no way to install Nix from the
official installer** — they get:

```
sorry, there is no binary distribution of Nix for your platform
```

This is the first thing a new user sees when they try Nix on non-x86/ARM
hardware. It's a hard stop.

## Current State

Three files in the [nix repository](https://github.com/NixOS/nix) control
installer platform support:

| File | Role |
|------|------|
| `packaging/installer/install.in` | Shell script downloaded from nixos.org. `case` on `uname -s.uname -m` selects the tarball. Falls through to error for unknown platforms. |
| `packaging/hydra.nix` | Hydra CI config. `installerScript` lists which platform tarballs to include in the installer. |
| `flake.nix` | Defines `crossSystems` — which platforms get cross-compiled packages and tarballs. |

### What's supported today

| Platform | `install.in` | `flake.nix` | Build method |
|----------|:---:|:---:|---|
| `x86_64-linux` | Yes | native | Hydra native builder |
| `i686-linux` | Yes | native | Hydra native builder |
| `aarch64-linux` | Yes | native | Hydra native builder |
| `x86_64-darwin` | Yes | native | Hydra native builder |
| `aarch64-darwin` | Yes | native | Hydra native builder |
| `armv6l-linux` | Yes | cross | Cross-compiled from x86_64-linux |
| `armv7l-linux` | Yes | cross | Cross-compiled from x86_64-linux |
| `riscv64-linux` | Yes | cross | Cross-compiled from x86_64-linux |

### What's missing

| Platform | `uname -m` | Who uses it | Community size |
|----------|-----------|------------|---------------|
| **`s390x-linux`** | `s390x` | IBM Z / LinuxONE — enterprise mainframes, banks, governments. [LinuxONE Community Cloud](https://www.ibm.com/linuxone) offers free VMs. 353 repos in [linux-on-ibm-z](https://github.com/linux-on-ibm-z) | Large enterprise |
| **`powerpc64le-linux`** | `ppc64le` | IBM POWER — HPC, AI training, scientific computing. [OpenPOWER Foundation](https://openpowerfoundation.org/) open hardware initiative. Runs major distros (Ubuntu, Fedora, RHEL, SUSE). Docker has official ppc64le images | Large HPC/enterprise |
| **`powerpc64-linux`** | `ppc64` | POWER big-endian — [Raptor Computing](https://www.raptorcs.com/) Talos II/Lite workstations. The only fully libre (FSF-endorsed) high-performance desktop hardware. Active community | Medium libre hardware |
| **`loongarch64-linux`** | `loongarch64` | LoongArch — Loongson 3A5000/6000 processors. Shipping in Chinese laptops, desktops, servers. Growing Linux ecosystem. Fedora, Gentoo, Arch have ports | Growing |
| **`riscv32-linux`** | `riscv32` | RISC-V 32-bit — embedded/IoT. ESP32-C3 (WiFi), GD32VF103 (MCU), Allwinner D1s. Millions of chips shipped. Linux runs on many of them | Large embedded |
| **`mips64el-linux`** | `mips64` | MIPS64 little-endian — Cavium Octeon network processors, some routers. Legacy but still deployed | Shrinking |

## Proposed Changes

Three patches (in `docs/patches/nix-installer/`):

### 1. `install.in.patch` — Add platform detection

Adds 6 new `case` entries to the `uname` detection. Each follows the existing
pattern exactly:

```sh
Linux.s390x)
    hash=@tarballHash_s390x-linux@
    path=@tarballPath_s390x-linux@
    system=s390x-linux
    ;;
```

**Note on `uname -m` values:** These must match exactly what the kernel reports.
Verified values:

| Platform | `uname -m` returns | Source |
|----------|-------------------|--------|
| IBM Z | `s390x` | Verified on LinuxONE Community Cloud |
| POWER LE | `ppc64le` | Standard Linux kernel |
| POWER BE | `ppc64` | Standard Linux kernel |
| LoongArch | `loongarch64` | [Linux kernel arch/loongarch](https://github.com/torvalds/linux/tree/master/arch/loongarch) |
| MIPS64 | `mips64` | Standard Linux kernel (note: LE and BE both report `mips64`) |
| RISC-V 32 | `riscv32` | Standard Linux kernel |

### 2. `flake.nix.patch` — Add cross-compilation targets

Adds the 5 new platforms to `crossSystems`. These will be **cross-compiled from
x86_64-linux** — no new native Hydra builders needed.

The patch organizes cross targets into two groups for clarity:
- **Tier 1** (existing): ARM and RISC-V 64-bit
- **Tier 2** (new): enterprise, HPC, and emerging architectures

### 3. `hydra.nix.patch` — Include tarballs in installer

Adds the new `binaryTarballCross` entries to `installerScript`, so the
generated `install.in` gets the hashes and paths substituted.

## Impact Assessment

### Hydra CI load

Each new cross-compilation target adds one `binaryTarball` job per release.
This job cross-compiles the `nix` closure (~50-100 packages) from x86_64-linux.
Estimated: **5-10 minutes per target** on Hydra.

6 new targets × ~10 min = **~1 hour additional CI time per release**. This is
negligible compared to the full Hydra workload.

### Installer script size

Each platform adds ~5 lines to `install.in`. The script grows from ~125 to
~160 lines. Negligible.

### Binary tarball hosting

Each tarball is ~40-60MB compressed. 6 new platforms × ~50MB = **~300MB
additional storage per release** on releases.nixos.org.

### Risk

**Low.** The cross-compilation infrastructure already exists and is used for
armv6l, armv7l, and riscv64. The new platforms use the same mechanism. If a
cross-compilation fails, it only affects that platform's tarball — it doesn't
break existing platforms.

The `mips64el` case has a subtlety: `uname -m` reports `mips64` for both
big-endian and little-endian MIPS64. The installer would need to detect
endianness (e.g., via `lscpu` or reading ELF header of `/bin/sh`) if both
are to be supported. For now, we assume little-endian (mips64el) as that's the
common case. This should be discussed with the Nix team.

## Tiered Rollout Strategy

We recommend proposing this as a tiered rollout to reduce review burden:

### Phase 1: s390x + powerpc64le (highest impact, proven)

- **s390x**: nix-on-z has Nix 2.35.0 fully bootstrapped and running. Proven.
- **powerpc64le**: Major distros support it. Docker has official images. Cross-compilation from x86_64 is well-tested in nixpkgs.

These two serve the largest unserved communities (enterprise + HPC) and are the
most likely to "just work" with cross-compilation.

### Phase 2: powerpc64 + loongarch64

- **powerpc64**: Talos II community is small but vocal and technically capable.
  They will test thoroughly.
- **loongarch64**: Growing ecosystem. May need nixpkgs patches for some
  packages, but the Nix package itself should cross-compile cleanly.

### Phase 3: riscv32 + mips64el

- **riscv32**: Embedded Linux on riscv32 is less common (many riscv32 boards run
  bare-metal or RTOS, not Linux). Worth supporting but lower priority.
- **mips64el**: Legacy architecture, shrinking community. Include for
  completeness but lowest priority.

## Testing Strategy

For each new platform, before proposing upstream:

1. **Cross-compile the nix binary tarball** from x86_64-linux:
   ```bash
   nix build .#hydraJobs.binaryTarballCross.x86_64-linux.s390x-unknown-linux-gnu
   ```

2. **Test on real hardware or QEMU**:
   ```bash
   # s390x (LinuxONE Community Cloud)
   scp result/*.tar.xz z:
   ssh z "tar xf nix-*.tar.xz && cd nix-* && ./install --no-daemon"

   # Other platforms (QEMU)
   qemu-system-ppc64le -M pseries ...
   qemu-system-s390x -M s390-ccw-virtio ...
   ```

3. **Run `nix build nixpkgs#hello`** to verify the installed Nix can fetch
   and build packages.

## What nix-on-z Has Already Proven

The nix-on-z project has:

- Bootstrapped Nix 2.35.0 on s390x from source (not cross-compiled)
- Built 200+ derivations natively on z15 hardware
- Fixed 5 s390x-specific build issues (OpenSSL, PCRE2, bison, zlib, system-features)
- Set `gcc.arch = z15` globally for hardware-optimized builds
- Currently building ClickHouse natively on s390x (in progress)

This proves that s390x is a viable Nix platform. The installer is the missing
piece that would let other s390x users get started without bootstrapping from
source.

## Files

```
docs/patches/nix-installer/
├── install.in.patch     # Platform detection in installer shell script
├── flake.nix.patch      # Cross-compilation targets
└── hydra.nix.patch      # Tarball inclusion in installer build
```

## Discussion Points for the Nix Team

1. **Hydra capacity:** Can Hydra handle 6 additional cross-compilation jobs per
   release? (We believe yes — they're small and fast.)

2. **Storage on releases.nixos.org:** Is ~300MB per release acceptable?

3. **Ongoing maintenance:** Who maintains cross-compilation for new platforms?
   The nix-on-z team can own s390x. The OpenPOWER community can own ppc64le.

4. **mips64 endianness detection:** How should the installer distinguish
   mips64el from mips64 big-endian? Or do we only support little-endian?

5. **Tiered rollout vs. all-at-once:** Would the Nix team prefer separate PRs
   per platform, or one PR with all 6?

6. **Native Hydra builders:** Long-term, adding native s390x and ppc64le
   builders to Hydra would enable native tarballs instead of cross-compiled
   ones. Is there appetite for this? IBM and OpenPOWER may donate hardware.

---

*Part of the [nix-on-z](https://github.com/) project. Last updated: 2026-03-31.*
