# S390X Nixpkgs Porting Guide

> Authoritative reference for porting the nixpkgs ecosystem to IBM s390x (Z architecture).

## Project Mission

Get the **entire nixpkgs ecosystem** building and running on s390x (IBM Z / LinuxONE).

The [nix-on-z](https://github.com/) project has already bootstrapped **Nix 2.35.0** on s390x.
The next step is to systematically port nixpkgs, leveraging the
[linux-on-ibm-z](https://github.com/linux-on-ibm-z) organization's **353 repositories**
of already-ported software.

## Where to Start

| I want to... | Go to |
|---|---|
| Port a package to s390x | [Nix Patterns](docs/nix-patterns.md) — copy-paste recipes |
| Check if someone already ported it | [Package Cross-Reference](docs/package-crossref.md) — linux-on-ibm-z mapping |
| Understand why my build failed | [Technical Reference](docs/technical-reference.md) — endianness, SIMD, JIT, seccomp |
| See what already works | [Current State](docs/current-state.md) — existing infrastructure and gaps |
| Know what to work on next | [Priority Plan](docs/priority-plan.md) — dependency graph analysis |
| Test an s390x build | [Porting Tests](docs/porting-testing.md) — cross-compilation, QEMU, native hardware |
| Reuse IBM's existing patches | [IBM Z Patch Reuse](docs/ibm-z-patch-reuse.md) — linux-on-ibm-z patch strategy |
| Submit a fix to nixpkgs | [Contributing](docs/contributing.md) — PR workflow and templates |
| See a complex port worked end-to-end | [ClickHouse Case Study](docs/example-clickhouse.md) — SIMD, JIT, endianness, bundled deps |

## Key Findings

### The build graph is a funnel

We analyzed the nix store database (102,872 paths, 1,001,713 dependency edges, 722 s390x
derivations) and ranked every s390x package by how many other packages break if it fails.
Full analysis: [Priority Plan](docs/priority-plan.md)

```
binutils (414) → glibc (297) → gcc-wrapper (289) → pkg-config (222) → bash (121)
    ↓                ↓               ↓                   ↓               ↓
Everything       Everything      Everything          Most C/C++      Build scripts
```

The top 8 packages (the cross-toolchain) already work — they're what produces the bootstrap
tarballs. The **risk zone** is packages 9-40 (pkg-config, bash, pcre2, zlib, openssl,
ncurses, libseccomp...) where s390x issues actually surface.

### 87% of tested packages already evaluate for s390x

We tested 30 packages with `nix build nixpkgs#pkgsCross.s390x.<pkg> --dry-run`. 26 passed.
Several (openssl, coreutils, pcre2) already have s390x binaries cached. Full results:
[Porting Tests](docs/porting-testing.md#initial-cross-compilation-test-matrix)

### Only 3 packages explicitly block big-endian

A scan of all of nixpkgs found just 3 packages using `badPlatforms = lib.platforms.bigEndian`:
`aws-c-common`, `skia-pathops`, `webrtc-audio-processing_1`. Details:
[Blockers](docs/blockers.md)

### Highest-impact fixes

| Fix | Effort | Unlocks |
|-----|--------|---------|
| Add s390x to OpenJDK `meta.platforms` | One-line | Entire JVM ecosystem (Kafka, Cassandra, Elasticsearch, Scala, Spark) |
| Add s390x to Grafana `meta.platforms` | One-line | Grafana monitoring stack |

Both are nixpkgs packaging gaps — upstream already supports s390x.

### Completed fixes (nix-on-z local patches)

| Fix | What it enables |
|-----|-----------------|
| `gcc.arch=z13` in `lib/systems/examples.nix` | Vector extensions for all s390x cross-builds |
| `s390x-multiplatform` in `lib/systems/platforms.nix` | Kernel config for s390x (bzImage, defconfig) |
| `linux64-s390x` in OpenSSL | CPACF hardware crypto acceleration |
| ClickHouse s390x support in `generic.nix` | Cross-compilation with SIMD disable, OpenSSL for gRPC, ICU BE fix |

## Top 10 s390x Target Libraries by Impact

These cross-compiled libraries have the most downstream dependents. If any break, the
listed number of other s390x packages also break.

| Rank | Package | Dependents | s390x-Specific Concern |
|------|---------|----------:|----|
| 1 | binutils | 414 | Toolchain — already working |
| 2 | glibc | 297 | Toolchain — already working |
| 3 | gcc-wrapper | 289 | Toolchain — already working |
| 4 | pkg-config | 222 | Works |
| 5 | bash | 121 | Works |
| 6 | pcre2 | 108 | JIT disabled (`--enable-jit=no`) |
| 7 | zstd | 101 | Portable C — should work |
| 8 | ncurses | 98 | Portable — should work |
| 9 | zlib | 95 | Has s390x DFLTCC hardware acceleration |
| 10 | openssl | 73 | Has s390x CPACF hardware crypto |

Full ranking of 39 packages: [Priority Plan](docs/priority-plan.md#s390x-target-libraries--ranked-by-transitive-impact)

## Porting Challenge Areas

The most common reasons packages fail on s390x, in order of frequency:

| Challenge | Frequency | Quick Fix | Details |
|---|---|---|---|
| **Endianness** | Most common | `isBigEndian` checks, byte-swap functions | [Technical Reference: Endianness](docs/technical-reference.md#endianness) |
| **x86 SIMD** | Common | Disable SSE/AVX, use scalar fallback | [Technical Reference: SIMD](docs/technical-reference.md#simd--vector-extension-facility) |
| **JIT compilation** | Occasional | Disable JIT flag | [Technical Reference: JIT](docs/technical-reference.md#jit-compilation) |
| **Seccomp/syscalls** | Occasional | Use libseccomp, symbolic syscall names | [Technical Reference: Seccomp](docs/technical-reference.md#seccomp--syscalls) |
| **Platform not listed** | Occasional | Add `"s390x-linux"` to `meta.platforms` | [Nix Patterns: Add to platform list](docs/nix-patterns.md#add-s390x-to-a-platform-list) |

## Document Map

```
S390X-PORTING-GUIDE.md          ← You are here (overview)
docs/
├── current-state.md             ← What exists in nixpkgs today + gaps
├── technical-reference.md       ← Architecture details, porting challenges, hardware features
├── nix-patterns.md              ← 10 copy-paste Nix expression recipes
├── package-crossref.md          ← 353 linux-on-ibm-z repos mapped to nixpkgs (10 categories)
├── blockers.md                  ← Big-endian blockers, implicit exclusions, analysis
├── priority-plan.md             ← Dependency graph analysis, tiered porting plan
├── porting-testing.md           ← Cross-compilation, QEMU, native hardware, test matrix
├── ibm-z-patch-reuse.md         ← linux-on-ibm-z patch reuse strategy and priorities
├── contributing.md              ← PR workflow, fetchpatch patterns, templates
├── debugging.md                 ← Binary inspection, QEMU, nix queries, graph analysis SQL
└── example-clickhouse.md        ← Case study: porting a complex C++ project end-to-end
```

## Scope

This guide covers Linux on Z only — not z/OS or z/VM. For general Nix packaging,
see the [nixpkgs manual](https://nixos.org/manual/nixpkgs/stable/).

---

*Part of the [nix-on-z](https://github.com/) project. Last updated: 2026-03-29.*
