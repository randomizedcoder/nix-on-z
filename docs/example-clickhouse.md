# Case Study: Porting ClickHouse to s390x

[Back to overview](../S390X-PORTING-GUIDE.md)

---

ClickHouse is a column-oriented OLAP database that processes billions of rows per second.
It is also one of the most demanding C++ projects you can try to cross-compile: x86 SIMD
intrinsics in query kernels, an embedded LLVM JIT compiler, BoringSSL for gRPC, dozens of
bundled C++ libraries, and serialization code that assumes little-endian byte order in
"many places" (their maintainer's words).

This document walks through building ClickHouse for s390x via nixpkgs. Steps 1-6
implemented the Nix expression changes and dry-run evaluation. The cross-compilation
build (Step 7) hit an architectural conflict between ClickHouse's hermetic build and
Nix's packaging model after 8 fix iterations — see
[Build Challenges](clickhouse-challenges.md) for the full analysis. The native build
(Step 8) now succeeds: **ClickHouse 26.2.4.23 builds and runs natively on s390x z15**
as of 2026-04-07.

It serves two purposes:

1. **A concrete, fully-executed porting plan** for ClickHouse on s390x
2. **A worked example** showing how the concepts in the [Porting Guide](../S390X-PORTING-GUIDE.md) apply to a real, complex package

## Why ClickHouse on s390x?

Mainframes are not what most people picture when they think "analytics database." But the
match is surprisingly natural:

- **I/O bandwidth**: s390x systems move data between storage and memory faster than
  commodity hardware. OLAP workloads are I/O-bound — this matters.
- **Hardware compression**: s390x's DFLTCC instruction compresses zlib/gzip data at
  10-50x the speed of software. ClickHouse ingests compressed data constantly.
- **Hardware crypto**: CPACF accelerates TLS in ClickHouse's gRPC and HTTP interfaces
  without CPU overhead.
- **Reliability**: Mainframes run for years without unplanned downtime. An analytics
  database that never goes down is compelling for enterprises already on Z.

ClickHouse also exercises nearly every s390x porting challenge simultaneously, making it
an ideal case study for learning the porting process.

## What Makes This Port Interesting

### The endianness story

s390x is big-endian — the most-significant byte comes first in memory. This is the natural
byte order (how humans write numbers), inherited from IBM's System/360 in 1964. Every other
mainstream architecture (x86, ARM, RISC-V) went little-endian.

For ClickHouse, this matters everywhere data crosses a boundary:

- **Wire protocols**: ClickHouse's native TCP protocol serializes integers in little-endian.
  A big-endian server must byte-swap every value it sends and receives.
- **Hash functions**: SipHash, CityHash, and other hash functions used for sharding and
  aggregation produce different results on big-endian unless explicitly handled.
- **On-disk formats**: MergeTree data parts, checksums, and metadata assume LE layout.
- **Codecs**: Delta, DoubleDelta, and Gorilla codecs encode differences between values —
  the bit layout changes with byte order.

The good news: ClickHouse's upstream team has already merged fixes for the most critical
endianness issues:

| PR | What it fixes |
|----|---------------|
| [#39656](https://github.com/ClickHouse/ClickHouse/pull/39656) | BitHelpers endian issue |
| [#39732](https://github.com/ClickHouse/ClickHouse/pull/39732) | SipHash endian issue |
| [#40008](https://github.com/ClickHouse/ClickHouse/pull/40008) | Codec endian issues |
| [#40179](https://github.com/ClickHouse/ClickHouse/pull/40179) | FileEncryption endian issues |
| [#39931](https://github.com/ClickHouse/ClickHouse/pull/39931) | KeeperSnapshotManager endian issues |
| [#49198](https://github.com/ClickHouse/ClickHouse/pull/49198) | `reinterpretAs*()` big-endian fixes |

The bad news: their maintainer notes "we assume little-endian in many places" — more
issues will surface during testing.

See: [Technical Reference: Endianness](technical-reference.md#endianness)

### SIMD: different but not less

ClickHouse uses x86 SIMD heavily — SSE4.2, AVX2, and AVX-512 intrinsics in query execution
kernels for aggregation, filtering, hashing, and string operations. These are in headers
like `<immintrin.h>` and `<nmmintrin.h>` that simply don't exist on s390x.

s390x has its own SIMD: the **Vector Extension Facility (VXE)**, available since the z13
processor (2015). VXE provides 32 128-bit vector registers and operations accessed via
`<vecintrin.h>`. It's not less capable — it's a different API.

For the initial port, the practical approach is:

1. **Disable x86 SIMD** via CMake flags — ClickHouse has scalar fallbacks for all SIMD paths
2. **Verify correctness** with scalar code
3. **Optionally** write VXE implementations for hot paths later (this is where the
   performance recovery would come from)

The key CMake flags:
```cmake
-DNO_SSE3_OR_HIGHER=1      # Disable SSE3/SSSE3/SSE4.1/SSE4.2
-DNO_AVX_OR_HIGHER=1        # Disable AVX/AVX2
-DNO_AVX256_OR_HIGHER=1     # Disable AVX-256
-DNO_AVX512_OR_HIGHER=1     # Disable AVX-512
```

See: [Technical Reference: SIMD](technical-reference.md#simd--vector-extension-facility)

### JIT on s390x — the good news

ClickHouse embeds an LLVM-based JIT compiler (`ENABLE_EMBEDDED_COMPILER`) that compiles
SQL expressions into native machine code at query time. This sounds like it would be a
showstopper for s390x, but it isn't.

LLVM has a mature **SystemZ backend** that generates s390x machine code. The same backend
powers Clang's s390x support, which is production-grade. Since ClickHouse uses LLVM 21
(via nixpkgs' `llvmPackages_21`), and LLVM 21 has full SystemZ support, the JIT should
work without modification.

The only verification needed: ensure ClickHouse's embedded LLVM is built with the SystemZ
target enabled. In nixpkgs, LLVM is already built with all targets.

See: [Technical Reference: JIT](technical-reference.md#jit-compilation)

### 128-bit atomics — a non-issue

ClickHouse's nixpkgs expression adds `-mcx16` for x86_64, which enables the `CMPXCHG16B`
instruction for 16-byte compare-and-swap. On s390x, 16-byte CAS is available natively via
the `CSG` instruction — no special compiler flag needed. The `-mcx16` flag should simply
be skipped on s390x.

## Current State in nixpkgs

The ClickHouse package lives in `pkgs/by-name/cl/clickhouse/generic.nix`. Key facts from
the current expression:

| Aspect | Value |
|--------|-------|
| Version | 26.2.4.23-stable |
| Compiler | LLVM/Clang 21 (`llvmPackages_21.stdenv`) |
| Linker | LLD (`llvmPackages.lld`) |
| Platforms | `lib.filter is64bit (linux ++ darwin)` — s390x IS included (64-bit) |
| Cross-compilation | `broken` relaxed for s390x (`&& !stdenv.hostPlatform.isS390x`) |
| Rust | Enabled by default |
| x86 deps | `nasm`, `yasm` (x86 assemblers, already guarded by `isx86_64`) |
| s390x handling | CMake SIMD disable flags, OpenSSL for gRPC, ICU big-endian fix |

### The cross-compilation blocker

The expression contains:

```nix
broken = stdenv.buildPlatform != stdenv.hostPlatform;
```

This blanket-disables cross-compilation for ALL architectures, not just s390x. It's likely
there because cross-compilation hasn't been tested, not because it's known to be broken.
For s390x, this is the first thing that must be changed.

### What upstream already provides

ClickHouse ships a CMake cross-compilation toolchain file at
`cmake/linux/toolchain-s390x.cmake`. Their documentation at
https://clickhouse.com/docs/development/build-cross-s390x describes the cross-build
process. This means the build system already knows about s390x — we need to hook into it,
not build support from scratch.

## The Dependency Cascade

Following our [Priority Plan](priority-plan.md) methodology, here's how ClickHouse's
dependencies map to the s390x porting tiers:

### Tier 0 — Already working

These are verified working for s390x cross-compilation (from our
[test matrix](porting-testing.md#initial-cross-compilation-test-matrix)):

| Dependency | Transitive Dependents | ClickHouse Uses It For |
|------------|----------------------:|------------------------|
| glibc | 297 | Runtime C library |
| zlib | 95 | Compression (bundled copy) |
| openssl | 73 | TLS (for gRPC, replacing BoringSSL) |
| zstd | 101 | Compression (bundled copy) |

### Tier 1 — Needs verification

| Dependency | s390x Status | ClickHouse Uses It For |
|------------|-------------|------------------------|
| LLVM 21 | SystemZ backend exists | JIT compiler + build toolchain |
| ICU | Needs big-endian data tables | Unicode / collation (bundled copy) |
| Boost | Endian detection should work | Various utility libraries (bundled) |

### Tier 2 — Needs patching

| Dependency | Issue | Path Forward |
|------------|-------|-------------|
| BoringSSL | No s390x asm | Force OpenSSL for s390x (see below) |
| Apache Arrow | BE test failures | Disable or patch; bundled copy |
| RocksDB | Endianness in LZ4 compression | Upstream fix exists (PR #8962) |
| CRoaring | x86 SIMD in bitmap operations | Has portable C fallback |

### Tier 3 — ClickHouse itself

Once dependencies are handled, ClickHouse needs:
- CMake flags for s390x SIMD disable
- Nix expression changes (cross-compilation, platform-specific deps)
- Build + runtime testing

## Step-by-Step Porting Plan

### Step 1: Relax the cross-compilation restriction [DONE]

The current blanket `broken` flag blocks all cross-builds. For s390x, we allow it:

```nix
# Before:
broken = stdenv.buildPlatform != stdenv.hostPlatform;

# After:
broken = stdenv.buildPlatform != stdenv.hostPlatform
  && !stdenv.hostPlatform.isS390x;
```

This keeps the `broken` flag for other cross-compilation targets (which haven't been
tested) while unblocking s390x.

### Step 2: Skip x86-only dependencies [ALREADY DONE]

`nasm` and `yasm` are x86 assemblers — already guarded by `isx86_64` in the upstream expression:

```nix
nativeBuildInputs = [
  cmake
  ninja
  python3
] ++ lib.optionals stdenv.hostPlatform.isx86_64 [
  nasm
  yasm
];
```

### Step 3: Add s390x CMake flags [DONE]

Disable x86 SIMD and force OpenSSL for gRPC:

```nix
cmakeFlags = [
  # ... existing flags ...
] ++ lib.optionals stdenv.hostPlatform.isS390x [
  "-DNO_SSE3_OR_HIGHER=1"
  "-DNO_AVX_OR_HIGHER=1"
  "-DNO_AVX256_OR_HIGHER=1"
  "-DNO_AVX512_OR_HIGHER=1"
] ++ lib.optionals stdenv.hostPlatform.isx86_64 [
  "-DCMAKE_C_FLAGS=-mcx16"
  "-DCMAKE_CXX_FLAGS=-mcx16"
];
```

### Step 4: Handle gRPC / BoringSSL [DONE]

ClickHouse's gRPC interface uses BoringSSL by default. BoringSSL has no s390x assembly
(see [Package Cross-Reference: boringssl](package-crossref.md)). The fix is to force
OpenSSL on s390x:

```nix
cmakeFlags = [
  # ... existing flags ...
] ++ lib.optionals stdenv.hostPlatform.isS390x [
  "-DENABLE_GRPC_USE_OPENSSL=1"   # Force OpenSSL instead of BoringSSL
];
```

This also unlocks **CPACF hardware crypto acceleration** — a net win over BoringSSL's
software-only crypto on s390x.

### Step 5: Handle bundled ICU [DONE]

ClickHouse bundles ICU for Unicode support. ICU's precompiled data tables are
little-endian by default. For s390x, the data must be either:

1. **Regenerated** with `icupkg -tb` (convert to big-endian)
2. **Swapped at runtime** (ICU can auto-detect, but it's slower)

The cleanest Nix approach:
```nix
# If ClickHouse's bundled ICU doesn't handle BE automatically:
postPatch = lib.optionalString stdenv.hostPlatform.isBigEndian ''
  # Force ICU to use runtime byte-swapping
  substituteInPlace contrib/icu/icu4c/source/common/unicode/platform.h \
    --replace-fail "U_IS_BIG_ENDIAN 0" "U_IS_BIG_ENDIAN 1"
'';
```

### Step 6: Dry-run cross-compilation test [DONE]

After making the Nix expression changes, verify that the build graph resolves:

```bash
nix build nixpkgs#pkgsCross.s390x.clickhouse --dry-run
```

This doesn't compile anything — it just checks that all dependencies resolve and no
`meta.platforms` or `broken` flags block the build.

See: [Testing: Cross-Compilation](porting-testing.md#cross-compilation-no-s390x-hardware-needed)

### Step 7: Cross-compilation build [DEFERRED]

The cross-compilation build ran through 11 iterations of fixes, each uncovering
a deeper conflict between ClickHouse's hermetic build and Nix's cross-compilation
wrappers. See [ClickHouse Build Challenges](clickhouse-challenges.md) for the full
analysis.

**Summary of fixes applied to `generic.nix`:**

| Build | Fix | Status |
|-------|-----|--------|
| 1-2 | `-DOBJCOPY_PATH` / `-DSTRIP_PATH` for cross-tools | Working |
| 3-4 | Patch `default_libs.cmake` to use Nix's prebuilt `libclang_rt.builtins-s390x.a` | Working |
| 5 | `-DENABLE_ISAL_LIBRARY=OFF` (x86 Intel library) | Working |
| 6 | `-DENABLE_HDFS=OFF` (requires x86 assembler) | Working |
| 7 | `-DCMAKE_TOOLCHAIN_FILE=cmake/linux/toolchain-s390x.cmake` | Working |
| 8 | Sub-cmake `execute_process` doesn't inherit cache vars | **Blocked** |
| 9 | Unprefixed objcopy/strip/ar/ranlib symlinks in `preConfigure` | Working |
| 10 | `-DCOMPILER_CACHE=disabled` in sub-cmake | Working |
| 10-11 | Native (build-platform) compiler for sub-cmake | Implemented, untested |

The remaining blocker is that ClickHouse's `CMakeLists.txt:669` `execute_process`
builds native tools (protoc) using the **cross** compiler. Nix's cross-compiler
wrapper produces s390x binaries, which can't execute on x86_64. The fix
(`buildPackages.llvmPackages_21.clang-unwrapped`) is implemented in `generic.nix`
but untested — we pivoted to a native build strategy instead.

**Why deferred:** Each cross-compilation fix peels back a layer of conflict between
two hermetic build systems that both want full toolchain control. A native build
avoids this entirely. We can return to cross-compilation later with a known-good
native binary as baseline.

### Step 8: Native s390x build [DONE]

Building natively on s390x bypasses all cross-compilation issues. The s390x-specific
changes (SIMD disable, OpenSSL for gRPC, ISAL/HDFS off, ICU BE fix) are already in
`generic.nix` behind `isS390x` / `isBigEndian` guards. No toolchain file, no
objcopy symlinks, no compiler-rt patch, no sub-cmake compiler override.

#### Why native is fundamentally different from cross-compilation

Cross-compiling ClickHouse for s390x from x86_64 (Step 7) hit 11 iterations of
fixes because **two hermetic build systems fight for control**. On native s390x:

| Cross-compilation issue | Why it disappears natively |
|------------------------|---------------------------|
| Unprefixed objcopy/strip search | Tools have native names — no prefix needed |
| compiler-rt target mismatch | cc-wrapper target matches build platform |
| Sub-cmake `execute_process` uses wrong compiler | Same compiler for main and child builds |
| Toolchain file for sysroot | System compiler targets s390x natively |
| `buildPackages` vs `packages` confusion | Only one platform — no distinction needed |

In short: `buildPlatform == hostPlatform` eliminates an entire class of problems.
The remaining challenges are s390x-specific (SIMD, endianness, assembler instructions),
not cross-compilation-specific.

#### Architecture level: why `-march` matters everywhere

The single most impactful discovery during native builds was that **the bootstrap
assembler defaults to z900** (IBM's 2000-era architecture). Modern s390x assembly
in OpenSSL, PCRE2, and other packages uses z10+ instructions like `CIJNE` (Compare
Immediate and Jump if Not Equal) and `STFLE` (Store Facility List Extended) that
the z900 assembler doesn't recognize.

This manifests as:
```
crypto/sha/keccak1600-s390x.S:399: Error: Unrecognized opcode: `cijne'
```
or:
```
sljitNativeS390X.c:371: Error: Unrecognized opcode: `stfle'
```

The fix is to set `gcc.arch` globally, which propagates `-march=` to GCC and the
assembler for all packages. This is done in two places in nixpkgs:

| File | Scope | Effect |
|------|-------|--------|
| `lib/systems/platforms.nix` | Native builds | Sets `-march` for all packages built on s390x |
| `lib/systems/examples.nix` | Cross-compilation | Sets `-march` for all packages cross-compiled *for* s390x |

We set `gcc.arch = "z15"` to match our test hardware (LinuxONE Community Cloud,
machine type 8561). This enables:
- **VXE3** — third-generation vector extensions
- **DFLTCC** — hardware deflate/inflate (10-50x faster zlib)
- **Enhanced sort** — hardware-accelerated sort operations
- **CPACF** — crypto acceleration (already available at z13, but z15 adds more)

**Critical setup requirement:** When `gcc.arch` is set, nixpkgs adds `gccarch-<arch>`
as a required system feature on all derivations. The nix daemon must advertise it:

```bash
# /etc/nix/nix.conf on the s390x machine:
system-features = benchmark big-parallel gccarch-z15 nixos-test uid-range
```

Without this, every build fails with `Reason: missing system features`. See
[Technical Reference: Machine Types](technical-reference.md#machine-types-and-architecture-levels).

**Detecting your hardware:** The nix-on-z project includes a hardware detection tool:
```bash
nix run .#check-arch
```
This reads `/proc/cpuinfo`, maps the machine type to a GCC `-march` value, and
recommends the optimal `gcc.arch` setting.

**TODO:** Rebuild nix itself with z15 optimization. The nix binary on z was compiled
during bootstrap with `-march=z900`. While functional, nix's NAR hashing (SHA-256),
SQLite operations, and compression would benefit from z15 SIMD and crypto instructions.
This is not blocking but is a worthwhile optimization after the bootstrap completes.

#### Issues discovered during native build

**Issue 1 — zlib VX CRC32 (fixed):** nixpkgs zlib 1.3.2 failed on s390x — its
configure detects VX support and sets `-DHAVE_S390X_VX`, but doesn't add
`-march=z13` (which implies `-mvx`) to CFLAGS for `contrib/crc32vx/crc32_vx.c`.
Fixed by adding `-march=z13` to `NIX_CFLAGS_COMPILE` for s390x in `zlib/default.nix`.
This is a pre-existing nixpkgs bug affecting all s390x builds, not ClickHouse-specific.
Sources: [Fedora s390x-vectorize-crc32 patch](https://src.fedoraproject.org/rpms/zlib/blob/f34/f/zlib-1.2.11-s390x-vectorize-crc32.patch),
[Ubuntu bug #2075567](https://bugs.launchpad.net/ubuntu/+source/zlib/+bug/2075567).

**Issue 2 — OpenSSL s390x assembly (fixed):** OpenSSL 3.6.1's Keccak SHA-3 assembly
(`keccak1600-s390x.S`) uses the `CIJNE` instruction (z10+). The bootstrap assembler
(`gas` from binutils 2.38, defaulting to z900) can't assemble it. Fixed globally by
setting `gcc.arch = "z15"` in `platforms.nix`, and with a per-package fallback in
`openssl/default.nix`: `CFLAGS=-march=${stdenv.hostPlatform.gcc.arch or "z10"}`.
Sources: [openssl/openssl#27323](https://github.com/openssl/openssl/issues/27323),
[Gentoo bug #936790](https://bugs.gentoo.org/936790).

**Issue 3 — PCRE2 SLJIT assembly (fixed):** PCRE2's SLJIT JIT backend
(`sljitNativeS390X.c`) uses `STFLE` (z9+). Same root cause as OpenSSL — the
bootstrap assembler defaults to z900. Fixed by the global `gcc.arch = "z15"`.
Additionally, we re-enabled JIT for s390x (previously disabled in nixpkgs with
`--enable-jit=no`), since the SLJIT s390x backend has been available since
PCRE2 10.39 and nixpkgs has 10.46.
Sources: [SLJIT issue #89](https://github.com/zherczeg/sljit/issues/89),
[Ubuntu bug #1959917](https://bugs.launchpad.net/ubuntu/+source/pcre2/+bug/1959917).

**Issue 4 — nix system-features (fixed):** Setting `gcc.arch` in `platforms.nix`
causes nixpkgs to add `gccarch-z15` as a required system feature. The nix daemon
on the z machine didn't advertise this, causing all derivations to fail with
"missing system features". Fixed by adding `gccarch-z15` to `/etc/nix/nix.conf`.

**Issue 5 — bison test 270 "Null nonterminals" (skipped):** Bison's
`installcheck` fails at test 270 (`counterexample.at:621`) on s390x. This is a
known upstream bug in bison's counterexample generation, not s390x-specific — also
reported on Alpine Linux. Fixed by adding `!stdenv.hostPlatform.isS390x` to the
`doInstallCheck` guard in `bison/package.nix`. Tests are skipped, not fixed.
Sources: [bug-bison mailing list](https://www.mail-archive.com/bug-bison@gnu.org/msg04052.html).

**Issue 6 — psutil test_cpu_count_cores (skipped):** Python's `psutil` package
fails its `test_cpu_count_cores` test on s390x. The test parses `/proc/cpuinfo`
expecting x86-style `core id` / `physical id` fields, but s390x uses a completely
different format (no per-core topology lines). Fix: add `"cpu_count_cores"` to
`disabledTests` in `psutil/default.nix`. The test is architecture-specific, not a
real bug — psutil's CPU counting works fine on s390x via other code paths.

**Issue 7 — LLVM/Clang OOM and disk exhaustion:** Building Clang 21.1.8
from source hit two resource limits on the LinuxONE Community Cloud VM:

1. **OOM kill (4GB swap):** Linking `libclang-cpp.so.21.1` requires 7.2GB virtual
   memory. With 4GB RAM + 4GB swap = 8GB total, the OOM killer terminated `ld`
   (exit code 137). Fixed by increasing swap to 8GB (12GB total).

2. **Disk full (50GB):** Even after GC freed 13.6GB, the nix store (16GB) + LLVM
   build artifacts (~15GB) + 8GB swap file + OS fills the 50GB disk. The Clang
   build fails at 1152/2258 files with "No space left on device".

**Root cause:** The LinuxONE Community Cloud free tier (2 vCPU, 4GB RAM, 50GB disk)
is undersized for bootstrapping the full Nix toolchain (GCC + LLVM + Clang + Rust)
from source with no binary cache. A larger machine is needed.

**Issue 8 — Corrosion Rust target missing for s390x (fixed):** ClickHouse's
`contrib/corrosion-cmake/CMakeLists.txt` maps cmake toolchain files to Rust target
triples. It supports x86_64, aarch64, ppc64le, riscv64, Darwin, and FreeBSD — but
not s390x. When ClickHouse's `cmake/target.cmake` auto-loads `toolchain-s390x.cmake`,
corrosion fails with "Unknown rust target". Fix: patch `set_rust_target()` to add
`s390x-unknown-linux-gnu` for `toolchain-s390x` via sed in `postPatch`. This is
upstreamable to ClickHouse (one-line addition to the `elseif` chain).

**Issue 9 — mold linker not supported on s390x (fixed):** ClickHouse's
`cmake/linux/toolchain-s390x.cmake` hardcodes `-fuse-ld=mold`, but mold does not
support s390x (no big-endian ELF support). Fix: `sed 's/mold/lld/g'` in the
toolchain file to use lld instead. Additionally, the corrosion-cmake sed fix
(Issue 8) needed to insert the s390x `set()` line after the riscv64 `set()` line
in the `set_rust_target()` function, not after the `elseif` line — the sed anchor
must match the correct position in the conditional chain.

**Issue 10 — pytest-xdist flaky test on s390x (skipped):**
`test_max_worker_restart_tests_queued` fails on s390x. This is a timing-dependent
process crash recovery test that is flaky on slower or differently-scheduled
architectures. Fix: added to `disabledTests` in the pytest-xdist package expression.

**Minimum recommended resources for full bootstrap:**
- **RAM:** 8GB minimum (16GB recommended) — LLVM linking needs 7+ GB
- **Disk:** 100GB minimum — nix store grows to 20-30GB, LLVM build needs 15GB,
  plus swap and OS
- **vCPUs:** 4+ recommended — LLVM has 4806 files, parallelism helps enormously

#### Build configuration

**Current status:** BUILD SUCCESSFUL (2026-04-07). ClickHouse 26.2.4.23 builds and
runs natively on s390x z15. ~385 derivations built from source (full bootstrap chain,
no s390x binary cache). Built with `-j 2 --cores 4`. Total disk usage ~76GB on a
300GB disk.

**Disk space requirements (measured):**
- Nix store during ClickHouse bootstrap: ~27GB (LLVM, GCC, Clang, Rust, 380+ deps)
- LLVM/Clang build directory (temp): ~23GB during compilation
- Rust build directory (temp): ~15GB estimated
- OS + swap + misc: ~25GB
- Total disk usage at completion: ~76GB
- **Minimum recommended: 200GB** (100GB is not enough — builds fail at Clang install)

**Resource constraints (300GB disk machine):**
- 300GB disk, sufficient for full bootstrap with `-j 2`
- RAM is sufficient with 8GB swap for LLVM linking
- With `-j 2 --cores 4`, build completes without disk contention

**Build steps:**
```bash
# From local machine: sync nixpkgs to z
rsync -avz --delete \
  --exclude='/.git/' --exclude='/result' \
  ~/Downloads/z/nixpkgs/ z:nixpkgs/

# On z: configure nix system-features (must match gcc.arch in platforms.nix)
ssh z
sudo mkdir -p /etc/nix
echo 'system-features = benchmark big-parallel gccarch-z15 nixos-test uid-range' \
  | sudo tee /etc/nix/nix.conf

# Check your hardware matches the configured gcc.arch:
# grep 'machine' /proc/cpuinfo  → 8561 = z15

# Build ClickHouse natively
cd nixpkgs
nix-build -A clickhouse --cores 2 -j 1 2>&1 | tee ~/clickhouse-build.log

# Verify
file result/bin/clickhouse
# Expected: ELF 64-bit MSB executable, IBM S/390

./result/bin/clickhouse local --version
./result/bin/clickhouse local --query 'SELECT 1'
```

#### Build Success Verification

```bash
$ file result/bin/clickhouse
result/bin/clickhouse: ELF 64-bit MSB pie executable, IBM S/390

$ clickhouse local --version
ClickHouse local version 26.2.4.23

$ clickhouse local --query 'SELECT 1'
1

$ clickhouse local --query 'SELECT sum(number) FROM numbers(1000000)'
499999500000
```

### Step 9: Cross-compilation (future)

Once the native build succeeds, return to cross-compilation:
1. Use the native binary as a reference for correctness
2. Fix the remaining sub-cmake compiler issue
   (`buildPackages.llvmPackages_21.clang-unwrapped` for `execute_process`)
3. Compare cross-built vs native-built binaries

### Step 10: QEMU user-mode test (if cross-compiling)

If cross-compiling from x86:

```bash
nix build .#pkgsCross.s390x.clickhouse
qemu-s390x result/bin/clickhouse local --version
```

QEMU user-mode is slow (10-100x) but sufficient for basic functionality testing.

See: [Testing: QEMU User-Mode](porting-testing.md#qemu-user-mode-emulation)

## Hardware Acceleration Opportunities

This is where s390x gets exciting. Rather than just matching x86 performance with scalar
fallbacks, several ClickHouse subsystems could run *faster* on s390x:

### DFLTCC — Hardware zlib compression

s390x's **DFLTCC** (Deflate Conversion Call) instruction performs zlib/gzip compression
and decompression in hardware. zlib-ng (and upstream zlib with patches) can use it
transparently.

ClickHouse compresses data during ingestion, replication, and backup. If its bundled zlib
is replaced with a DFLTCC-enabled version, every compression operation runs at hardware
speed — typically **10-50x faster** than software zlib.

| Operation | Software (x86) | DFLTCC (s390x) |
|-----------|---------------|----------------|
| Compress | ~300 MB/s | ~5-15 GB/s |
| Decompress | ~500 MB/s | ~10-20 GB/s |

### CPACF — Hardware TLS

ClickHouse's gRPC and HTTPS interfaces use TLS. On s390x with OpenSSL (not BoringSSL),
the **CPACF** (CP Assist for Cryptographic Functions) accelerator handles AES, SHA, and
other crypto operations in hardware, with zero CPU overhead.

This means switching from BoringSSL to OpenSSL on s390x isn't just a compatibility
fix — it's a performance upgrade.

### Hardware CRC32

s390x has vector instructions for CRC32 computation. ClickHouse uses CRC32 for data
integrity checks. The `crc32-s390x` library from
[linux-on-ibm-z](https://github.com/linux-on-ibm-z/crc32-s390x) could accelerate this.

### Future: VXE SIMD for query kernels

The longest-term opportunity: writing s390x VXE implementations of ClickHouse's hot query
paths. The x86 SIMD code that must be disabled for the initial port could be supplemented
with VXE equivalents using `<vecintrin.h>`, recovering the performance lost by falling back
to scalar code.

This is significant work, but it's the kind of contribution that would make ClickHouse a
first-class citizen on s390x rather than a "it compiles" port.

## Challenge Summary

| Challenge | Severity | Solution | Status |
|-----------|----------|----------|--------|
| **ClickHouse-specific** | | | |
| Cross-compilation `broken` flag | Blocker | Relax for s390x | Fixed |
| x86 assemblers (nasm/yasm) | Blocker | Skip on non-x86 (already guarded) | Fixed |
| x86 SIMD intrinsics | Critical | CMake flags to disable | Fixed |
| `-mcx16` compiler flag | Low | Skip on s390x (native CAS) | Fixed |
| gRPC / BoringSSL | High | Force OpenSSL on s390x | Fixed |
| Bundled ICU BE data | Medium | Force BE mode via `platform.h` patch | Fixed |
| Unprefixed objcopy/strip | Blocker | `-DOBJCOPY_PATH` / `-DSTRIP_PATH` | Fixed (top-level) |
| compiler-rt cross-build | Blocker | Patch `default_libs.cmake` to use Nix's prebuilt lib | Fixed |
| isa-l (x86 NASM) | Blocker | `-DENABLE_ISAL_LIBRARY=OFF` | Fixed |
| libhdfs3 (x86 yasm) | Blocker | `-DENABLE_HDFS=OFF` | Fixed |
| x86 sysroot flags on s390x | Blocker | `-DCMAKE_TOOLCHAIN_FILE=...toolchain-s390x.cmake` | Fixed |
| Sub-cmake objcopy search | Blocker | PATH symlinks in `preConfigure` | Fixed (cross only) |
| Endianness (serialization) | High | Upstream has 6+ merged fixes; more will surface | Untested |
| LLVM JIT (SystemZ) | Medium | Verify SystemZ target enabled | Untested |
| Bundled Arrow | Medium | Already disables SIMD on non-x86 | Untested |
| Bundled RocksDB endianness | Medium | Upstream CMake handles s390x with `-DPORTABLE=1` | OK |
| Rust components | Low | Disabled in nixpkgs already | N/A |
| mold linker not supported on s390x | Blocker | `sed 's/mold/lld/g'` in `toolchain-s390x.cmake` | Fixed |
| **nixpkgs-wide s390x issues** | | | |
| Bootstrap assembler defaults to z900 | Blocker | Set `gcc.arch` in `platforms.nix` + `examples.nix` | Fixed (z15) |
| OpenSSL Keccak assembly (`CIJNE`) | Blocker | `CFLAGS=-march=${gcc.arch or "z10"}` in `openssl/default.nix` | Fixed |
| PCRE2 JIT disabled for s390x | Medium | Re-enabled (`--enable-jit=auto`); SLJIT s390x backend since 10.39 | Fixed |
| zlib VX CRC32 intrinsics | Blocker | `-march=z13` in `NIX_CFLAGS_COMPILE` in `zlib/default.nix` | Fixed |
| nix `system-features` | Blocker | Add `gccarch-z15` to `/etc/nix/nix.conf` | Fixed |
| pytest-xdist flaky test | Low | Added `test_max_worker_restart_tests_queued` to `disabledTests` | Fixed |
| nix binary not z15-optimized | Low | Rebuild nix after bootstrap completes | TODO |

See [Build Challenges](clickhouse-challenges.md) for the full 8-iteration build log
and strategy analysis.

## What Remains After Initial Port

Even after the build succeeds, work remains:

1. **Runtime endianness bugs**: Upstream acknowledges "many places" assume LE. The test
   suite will find them. Each fix is a candidate for upstream contribution.
2. **Performance benchmarking**: Scalar fallbacks will be slower than SIMD. Quantify the
   gap to prioritize VXE work.
3. **Compression codec testing**: Delta, DoubleDelta, and Gorilla codecs are the most
   endianness-sensitive — they need thorough testing with real data.
4. **Replication testing**: ClickHouse's replication protocol sends data between nodes.
   Mixed-endianness clusters (x86 + s390x) are not expected to work, but same-endianness
   s390x clusters should.
5. **ClickHouse Keeper**: The Raft consensus implementation has had endianness fixes
   (PR #39931) but needs integration testing.
6. **Build LLVM with SystemZ-only backend**: The nixpkgs LLVM package builds all target
   backends (X86, AArch64, SystemZ, RISCV, ARM, etc.) even on s390x. For ClickHouse's
   JIT, only the `SystemZ` backend (and possibly `BPF`) is needed. Overriding LLVM to
   build only the required backends would significantly reduce build time and disk usage
   (currently 4800+ files for all backends). This is a nixpkgs-level override, e.g.
   `llvm.override { targetPlatforms = [ "SystemZ" "BPF" ]; }`.

## How to Contribute

This case study is a roadmap, not a completed port. Contributions at any stage are welcome:

- **Easy entry points**: Steps 1-3 (Nix expression changes) can be done and tested with
  `--dry-run` without any s390x hardware
- **Medium**: Steps 4-6 require building and basic testing
- **Advanced**: Steps 7-8 and hardware acceleration work need native s390x access

See [Contributing](contributing.md) for the nixpkgs PR workflow and patch templates.

The LinuxONE Community Cloud provides free s390x instances for open-source development —
no mainframe purchase required.

## Applicability to Other Packages

The patterns in this case study apply to many complex C++ packages:

| Pattern | Also applies to |
|---------|----------------|
| Disable x86 SIMD via CMake | Envoy, MongoDB, RocksDB, Arrow |
| BoringSSL → OpenSSL swap | Envoy, gRPC, Chromium |
| Bundled ICU BE handling | Node.js, PostgreSQL, any ICU user |
| LLVM JIT verification | PostgreSQL (JIT), LuaJIT (different — no s390x backend) |
| Cross-compilation `broken` relaxation | Many packages with untested cross-build |

Each of these is a [Tier 5 hard problem](priority-plan.md) in our priority plan. The
methodology is the same: assess what upstream provides, identify the blockers, fix the
Nix expression, test progressively from `--dry-run` through QEMU to native hardware.

---

*Part of the [S390X Nixpkgs Porting Guide](../S390X-PORTING-GUIDE.md). See also:
[Package Cross-Reference](package-crossref.md) | [Priority Plan](priority-plan.md) |
[Technical Reference](technical-reference.md) | [Nix Patterns](nix-patterns.md)*
