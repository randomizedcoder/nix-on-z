# Case Study: Porting ClickHouse to s390x

[Back to overview](../S390X-PORTING-GUIDE.md)

---

ClickHouse is a column-oriented OLAP database that processes billions of rows per second.
It is also one of the most demanding C++ projects you can try to cross-compile: x86 SIMD
intrinsics in query kernels, an embedded LLVM JIT compiler, BoringSSL for gRPC, dozens of
bundled C++ libraries, and serialization code that assumes little-endian byte order in
"many places" (their maintainer's words).

This document walks through building ClickHouse for s390x via nixpkgs. Steps 1-6 have
been implemented and the dry-run evaluation succeeds. The cross-compilation build
(Step 7) hit an architectural conflict between ClickHouse's hermetic build and Nix's
packaging model after 8 fix iterations — see
[Build Challenges](clickhouse-challenges.md) for the full analysis and strategy
evaluation.

It serves two purposes:

1. **A concrete, partially-executed porting plan** for ClickHouse on s390x
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

### Step 8: Native s390x build [IN PROGRESS]

Building natively on s390x bypasses all cross-compilation issues. The s390x-specific
changes (SIMD disable, OpenSSL for gRPC, ISAL/HDFS off, ICU BE fix) are already in
`generic.nix` behind `isS390x` / `isBigEndian` guards. No toolchain file, no
objcopy symlinks, no compiler-rt patch, no sub-cmake compiler override.

**Current status:** Build started on z (2026-03-31) via `tmux` session `clickhouse`.
Dry-run evaluation passed — 385 derivations to build (full bootstrap chain since
no s390x binary cache). Running with `--cores 1 -j 1` to stay within 4GB RAM.
Monitor via `ssh z "tail -20 ~/clickhouse-build.log"`.

**Prerequisites:**
- s390x machine with Nix installed (available via `ssh z`)
- `system-features = big-parallel` in `/etc/nix/nix.conf` on z (ClickHouse
  requires this feature flag)
- Sync modified nixpkgs to z

**Resource constraints (z machine):**
- 2 vCPUs, 4GB RAM, 33GB free disk
- ClickHouse takes 7+ hours on 2 cores and can use 8GB+ RAM during linking
- May need swap configured, or `NIX_BUILD_CORES=1` to limit memory pressure
- 33GB disk should be sufficient (ClickHouse build artifacts ~5-10GB)

**Build steps:**
```bash
# From local machine: sync nixpkgs to z
rsync -avz --delete \
  --exclude='/.git/' --exclude='/result' \
  ~/Downloads/z/nixpkgs/ z:nixpkgs/

# On z: configure nix for big-parallel builds
ssh z
echo 'system-features = nixos-test benchmark big-parallel' | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon

# Build ClickHouse natively (will take many hours on 2 cores)
cd nixpkgs
nix build .#clickhouse

# Verify
file result/bin/clickhouse
# Expected: ELF 64-bit MSB executable, IBM S/390

./result/bin/clickhouse local --version
./result/bin/clickhouse local --query 'SELECT 1'
```

**Expected issues on native build:**
- **Memory pressure**: Linking ClickHouse can require 8GB+. With 4GB RAM, the
  OOM killer may intervene. Mitigation: add swap, or set `NIX_BUILD_CORES=1`
- **Vendored sysroot deletion**: `postFetch` removes `contrib/sysroot/linux-*`
  (for macOS case-insensitivity fix). Without the toolchain file, cmake should
  use the system glibc — but some contrib cmake files may reference the sysroot
  directory and fail when it's missing
- **x86 assumptions in contrib**: Some of the 150+ bundled libraries may have
  hardcoded x86 flags not guarded by architecture checks
- **Rust**: Disabled in nixpkgs expression, but cmake may still probe

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
| Sub-cmake objcopy search | Blocker | PATH symlinks in `preBuild` (proposed) | **Blocked** |
| Endianness (serialization) | High | Upstream has 6+ merged fixes; more will surface | Untested |
| LLVM JIT (SystemZ) | Medium | Verify SystemZ target enabled | Untested |
| Bundled Arrow | Medium | Already disables SIMD on non-x86 | Untested |
| Bundled RocksDB endianness | Medium | Upstream fix exists | Untested |
| Rust components | Low | Disabled in nixpkgs already | N/A |

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
