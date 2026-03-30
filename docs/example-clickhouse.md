# Case Study: Porting ClickHouse to s390x

[Back to overview](../S390X-PORTING-GUIDE.md)

---

ClickHouse is a column-oriented OLAP database that processes billions of rows per second.
It is also one of the most demanding C++ projects you can try to cross-compile: x86 SIMD
intrinsics in query kernels, an embedded LLVM JIT compiler, BoringSSL for gRPC, dozens of
bundled C++ libraries, and serialization code that assumes little-endian byte order in
"many places" (their maintainer's words).

This document walks through what it would take to build ClickHouse for s390x via nixpkgs.
It serves two purposes:

1. **A concrete porting plan** for anyone who wants to tackle ClickHouse
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
| Cross-compilation | `broken = stdenv.buildPlatform != stdenv.hostPlatform` |
| Rust | Enabled by default |
| x86 deps | `nasm`, `yasm` (x86 assemblers) |
| s390x handling | None — zero references to `isS390x` or `isBigEndian` |

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
[test matrix](testing.md#initial-cross-compilation-test-matrix)):

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

### Step 1: Relax the cross-compilation restriction

The current blanket `broken` flag blocks all cross-builds. For s390x, we want to allow it:

```nix
# Before:
broken = stdenv.buildPlatform != stdenv.hostPlatform;

# After:
broken = stdenv.buildPlatform != stdenv.hostPlatform
  && !stdenv.hostPlatform.isS390x;
```

This keeps the `broken` flag for other cross-compilation targets (which haven't been
tested) while unblocking s390x.

### Step 2: Skip x86-only dependencies

`nasm` and `yasm` are x86 assemblers — useless on s390x:

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

### Step 3: Add s390x CMake flags

Disable x86 SIMD and the x86 `cmpxchg16b` flag:

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

### Step 4: Handle gRPC / BoringSSL

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

### Step 5: Handle bundled ICU

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

### Step 6: Dry-run cross-compilation test

After making the Nix expression changes, verify that the build graph resolves:

```bash
nix build nixpkgs#pkgsCross.s390x.clickhouse --dry-run
```

This doesn't compile anything — it just checks that all dependencies resolve and no
`meta.platforms` or `broken` flags block the build.

See: [Testing: Cross-Compilation](testing.md#cross-compilation-no-s390x-hardware-needed)

### Step 7: QEMU user-mode test

Build and run with QEMU:

```bash
# Build for s390x (will take a long time on x86)
nix build nixpkgs#pkgsCross.s390x.clickhouse

# Verify binary
file result/bin/clickhouse
# Expected: ELF 64-bit MSB executable, IBM S/390

# Run with QEMU user-mode
qemu-s390x result/bin/clickhouse local --version
```

QEMU user-mode is slow (10-100x) but sufficient for basic functionality testing. Don't
try to benchmark with it.

See: [Testing: QEMU User-Mode](testing.md#qemu-user-mode-emulation)

### Step 8: Native hardware test

For real testing, use the **LinuxONE Community Cloud** (free tier):

1. Provision a LinuxONE instance
2. Install Nix
3. Build ClickHouse natively
4. Run the ClickHouse test suite
5. Benchmark against x86 results

Native builds will expose runtime endianness issues that cross-compilation can't catch.

See: [Testing: Native Hardware](testing.md)

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

| Challenge | Severity | Solution | Effort |
|-----------|----------|----------|--------|
| Cross-compilation `broken` flag | Blocker | Relax for s390x | Trivial |
| x86 assemblers (nasm/yasm) | Blocker | Skip on non-x86 | Trivial |
| x86 SIMD intrinsics | Critical | CMake flags to disable | Easy |
| `-mcx16` compiler flag | Low | Skip on s390x (native CAS) | Trivial |
| Endianness (serialization) | High | Upstream has 6+ merged fixes; more will surface | Medium |
| gRPC / BoringSSL | High | Force OpenSSL on s390x | Easy |
| Bundled ICU BE data | Medium | Force BE mode or runtime swap | Medium |
| LLVM JIT (SystemZ) | Medium | Verify SystemZ target enabled | Easy |
| Bundled Arrow | Medium | Already disables SIMD on non-x86 | Easy |
| Bundled RocksDB endianness | Medium | Upstream fix exists | Easy |
| Rust components | Low | Disabled in nixpkgs already | None |

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
