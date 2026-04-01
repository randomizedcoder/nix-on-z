# ClickHouse s390x: Build Challenges and Strategy Analysis

[Back to overview](../S390X-PORTING-GUIDE.md) | [Case Study](example-clickhouse.md)

---

Cross-compiling ClickHouse for s390x via nixpkgs required 8 build iterations.
Each fix uncovered a deeper conflict between ClickHouse's "hermetic build" philosophy
and Nix's packaging model. This document captures what we learned and evaluates
strategies going forward.

## 8 Builds, 8 Problems

| Build | Error | Root Cause | Fix Applied |
|-------|-------|-----------|-------------|
| 1-2 | `Cannot find objcopy` | ClickHouse searches for unprefixed `objcopy`; Nix provides `s390x-unknown-linux-gnu-objcopy` | `-DOBJCOPY_PATH=...` / `-DSTRIP_PATH=...` cmake cache vars |
| 3-4 | `stubs-32.h not found` (compiler-rt) | ClickHouse builds compiler-rt from source; Nix's cc-wrapper sets `CMAKE_CXX_COMPILER_TARGET` to build platform, not host | Patch `default_libs.cmake` via sed to use Nix's prebuilt `libclang_rt.builtins-s390x.a` |
| 5 | `NASM required` (isa-l) | Intel Storage Acceleration Library needs x86 NASM assembler; cmake `option()` overrides the `NOT ARCH_AMD64` guard | `-DENABLE_ISAL_LIBRARY=OFF` |
| 6 | `yasm required` (libhdfs3) | HDFS library needs yasm x86 assembler, not guarded for s390x | `-DENABLE_HDFS=OFF` |
| 7 | `-march=x86-64-v2 -mpclmul` on s390x | Without ClickHouse's toolchain file, cmake uses x86_64 bundled sysroot with hardcoded x86 flags | `-DCMAKE_TOOLCHAIN_FILE=cmake/linux/toolchain-s390x.cmake` |
| 8 | `Cannot find objcopy` (again, sub-cmake) | The toolchain file launches a sub-cmake `execute_process` that doesn't inherit our cache vars | **Unsolved** |

Build 8 is where we stopped. The sub-cmake issue is architectural: ClickHouse's
`CMakeLists.txt` uses `execute_process(cmake ...)` to build native helper tools
in a child process. That child doesn't see our `-DOBJCOPY_PATH` cache variable,
and ClickHouse's toolchain file searches for unprefixed `objcopy` which doesn't
exist in a Nix cross-compilation environment.

## The Fundamental Tension

ClickHouse and Nix both want **hermetic, reproducible builds** — but they achieve
it through incompatible mechanisms:

| Component | What ClickHouse Does | What Nix Expects |
|-----------|---------------------|-----------------|
| **compiler-rt** | Builds `libclang_rt.builtins` from `contrib/llvm-project/compiler-rt` | Provides as separate `compiler-rt` package |
| **libc++ / libc++abi** | Builds from `contrib/llvm-project/libcxx` with `-nostdinc++` | Provides as `llvmPackages.libcxx` |
| **libunwind** | Builds from `contrib/llvm-project/libunwind` | Provides as `llvmPackages.libunwind` |
| **sysroot (glibc)** | Vendors headers/libs from Ubuntu 18.04 Docker image in `contrib/sysroot/` | Provides glibc as a derivation |
| **objcopy/strip** | Searches for unprefixed tools, builds native tools via `execute_process` | Provides prefixed cross-tools via `bintools` |
| **150+ libraries** | All in `contrib/` — boost, icu, openssl, zlib, protobuf, grpc, arrow... | Each is a separate nixpkgs derivation |

Each row is a friction point. The problem isn't that either system is wrong — it's
that two hermetic build systems each want full control of the toolchain and
dependency tree. Nix's cc-wrapper, environment variables, and package substitution
conflict with ClickHouse's assumptions at every layer.

### What Upstream ClickHouse Already Does for s390x

ClickHouse has official s390x support. Their `cmake/target.cmake` disables only
3 features:

```cmake
elseif (ARCH_S390X)
    set (ENABLE_GRPC OFF CACHE INTERNAL "")
    set (ENABLE_ARROW_FLIGHT OFF CACHE INTERNAL "")
    set (ENABLE_RUST OFF CACHE INTERNAL "")
```

Our nixpkgs expression adds 7 more flags on top. We're not fighting upstream —
we're fighting the **interaction between upstream's hermetic build and Nix's
hermetic build**.

## Strategies

### Strategy A: Unbundle and Nixify (Redpanda-style)

Create a new ClickHouse derivation that replaces ClickHouse's vendored components
with nixpkgs packages. The [redpanda Nix build](/home/das/Downloads/redpanda/nix/)
attempted this for a complex C++ project with Bazel. Their approach:

1. **`*-static.nix` wrappers** (8 packages: croaring, c-ares, hwloc, xxhash,
   ada, base64, libxml2, lksctp) — override nixpkgs packages with build flags
   matching what Bazel expects (e.g., `-DROARING_DISABLE_AVX=ON`)
2. **Replace vendored tools** (protoc, python with jinja2/jsonschema) with
   nixpkgs versions
3. **patchelf downloaded binaries** to use Nix store interpreter/RPATH

However, redpanda ultimately hit the same wall: **two hermetic build systems don't
compose**. Their Bazel build is currently blocked on sandbox conflicts, and they're
pursuing a Bazel fork with first-class Nix integration. This is a cautionary tale
for Strategy A — even with significant effort, the hermetic-vs-hermetic conflict
may resurface at deeper layers.

For ClickHouse this would mean:

- Replace `contrib/sysroot/` with Nix's glibc/headers
- Replace bundled compiler-rt, libc++, libunwind with `llvmPackages.*`
- Replace bundled openssl, zlib, icu, boost, protobuf, etc. with nixpkgs versions
- Disable ClickHouse's toolchain file entirely — let Nix control the toolchain
- Create `*-static.nix` wrappers where needed for ABI compatibility

**Pros:** Fully idiomatic Nix. Cross-compilation "just works." Binary cache friendly.
Upstreamable.

**Cons:** Massive effort (150+ bundled libraries). Version skew risk. ABI
compatibility across static libs. ClickHouse actively resists unbundling.

**Estimate:** Weeks of work.

### Strategy B: Let ClickHouse Be ClickHouse (Minimal Nix Wrapper)

Accept ClickHouse's hermetic build and focus on making Nix provide just the outer
shell. Similar to how nixpkgs handles Chromium:

- Keep ClickHouse's toolchain file and vendored deps
- Fix only the Nix-specific friction points (objcopy paths, compiler-rt, etc.)
- Use `preBuild` to symlink/inject Nix tools where ClickHouse expects them
- Treat it as a "foreign package"

**Pros:** Fewer changes. Less version-skew risk. Closer to what ClickHouse CI tests.
The remaining objcopy issue is likely solvable with a targeted fix.

**Cons:** Not fully idiomatic Nix. Harder to cache intermediate steps.
Cross-compilation requires ongoing maintenance.

**Estimate:** Days. Fix the remaining objcopy sub-cmake issue, possibly 1-2 more.

### Strategy C: Hybrid (Selective Unbundling)

Unbundle only the high-value, easy-to-replace components:

- **Replace**: openssl (for CPACF hardware crypto), zlib (for DFLTCC hardware
  compression), icu (for endianness)
- **Keep**: compiler-rt, libc++, sysroot, 140+ other contrib libs
- **Fix**: tooling issues (objcopy, strip) via PATH manipulation

This gets the hardware acceleration benefits without the full unbundling effort.

**Pros:** Best ROI — hardware accel from nixpkgs openssl/zlib, minimal disruption.
Targeted, achievable scope. Still upstreamable.

**Cons:** Still need to solve the sub-cmake objcopy issue. Partial unbundling may
create new friction at library boundaries.

## Recommended Path: Native First, Cross Later

### Cross-compilation progress (builds 9-11)

After documenting the 8 build iterations, three more attempts were made:

| Build | Fix Applied | New Error |
|-------|------------|-----------|
| 9 | Unprefixed objcopy/strip/ar/ranlib symlinks in `preConfigure` | Sub-cmake fails: missing `-DCOMPILER_CACHE=disabled` |
| 10 | Added `-DCOMPILER_CACHE=disabled` to sub-cmake via sed | Used `stdenv.cc.cc` which resolved to GCC, not clang; binary not found |
| 11 | Used `llvmPackages.clang-unwrapped` for native compiler | "Exec format error" — `clang-unwrapped` was the s390x binary, can't run on x86_64 |

Build 9 proved the objcopy fix works (`-- Using objcopy: /build/cross-tools/objcopy`).
Builds 10-11 revealed a deeper problem: the sub-cmake `execute_process` at
`CMakeLists.txt:669` builds native tools (protoc) but forwards the cross compiler.
Finding the right build-platform clang in Nix's cross-compilation context requires
`buildPackages.llvmPackages_21.clang-unwrapped` — now implemented but untested.

### Why native-first is better

All cross-compilation blockers (builds 8-11) stem from ClickHouse's `execute_process`
sub-cmake not composing with Nix's cross-compilation wrappers. On native s390x:

- `buildPlatform == hostPlatform` — no cross wrappers, no prefixed tools
- No toolchain file needed — system compiler targets s390x natively
- No compiler-rt patch — cc-wrapper target matches
- No objcopy symlinks — tools have native names
- No sub-cmake compiler override — same compiler for main and native builds

The only s390x-specific changes for a native build are:
1. SIMD disable flags (already implemented)
2. OpenSSL for gRPC (already implemented)
3. ISAL/HDFS disable (already implemented)
4. ICU big-endian fix (already implemented)

All four are already in `generic.nix` behind `isS390x` / `isBigEndian` guards.

### The bootstrap assembler problem

While cross-compilation has its own class of issues (toolchain wrappers, prefixed
tools, platform mismatches), native builds revealed a different challenge:
**the bootstrap toolchain is too old for modern s390x assembly**.

The nixpkgs bootstrap for s390x uses binutils 2.38 with `gas` defaulting to the
z900 instruction set (IBM's 2000-era architecture). Modern packages like OpenSSL
and PCRE2 have s390x assembly that uses z10+ instructions:

| Package | Assembly file | Failing instruction | Minimum arch |
|---------|--------------|--------------------:|-------------|
| OpenSSL | `keccak1600-s390x.S` | `CIJNE` (Compare Immediate and Jump if Not Equal) | z10 (2008) |
| PCRE2/SLJIT | `sljitNativeS390X.c` | `STFLE` (Store Facility List Extended) | z9 (2006) |

The fix is to set `gcc.arch` globally in nixpkgs, which propagates `-march=` to
GCC and the assembler for every package in the dependency graph:

```nix
# lib/systems/platforms.nix (native builds):
s390x-multiplatform = {
  gcc.arch = "z15";  # match your hardware
  linux-kernel = { ... };
};

# lib/systems/examples.nix (cross-compilation):
s390x = {
  config = "s390x-unknown-linux-gnu";
  gcc = { arch = "z15"; };
};
```

**Important:** Setting `gcc.arch` also requires adding `gccarch-z15` to the nix
daemon's `system-features` in `/etc/nix/nix.conf`. Without this, nixpkgs
derivations fail with "missing system features". See
[Technical Reference: Machine Types](technical-reference.md#machine-types-and-architecture-levels).

**Choosing the right arch level:** The `-march` value should match your target
hardware. Higher values enable more hardware features but exclude older machines:

| Machine type | `-march` | Key features gained |
|-------------|----------|-------------------|
| 2964/2965 (z13) | `z13` | VXE (vector SIMD) |
| 3906/3907 (z14) | `z14` | VXE2 |
| 8561/8562 (z15) | `z15` | DFLTCC (hardware deflate), VXE3, sort |
| 3931/3932 (z16) | `z16` | NNPA (AI accelerator) |
| 9175 (z17) | `arch15` | Requires GCC 15+ |

Use `grep 'machine' /proc/cpuinfo` to check, or `nix run .#check-arch` to
auto-detect and recommend.

### Cross-compilation vs native: lessons learned

| Concern | Cross-compilation (x86→s390x) | Native (s390x→s390x) |
|---------|-------------------------------|----------------------|
| **Toolchain control** | Two hermetic systems fight (Nix vs ClickHouse). 11 iterations of fixes. | One system. No wrapper conflicts. |
| **Assembler instructions** | Cross-assembler honors `-march` from `examples.nix` | Bootstrap assembler defaults to z900. Must set `gcc.arch` in `platforms.nix`. |
| **Build speed** | Fast x86 compilation, but can't test the binary | Slow (2 cores, 4GB RAM, hours of bootstrap), but produces runnable binary |
| **Binary cache** | x86 toolchain is cached; only cross-compiled outputs are new | No s390x cache. Every derivation builds from source (~385 packages). |
| **Configuration** | `examples.nix` + `crossSystem` in flake | `platforms.nix` + `/etc/nix/nix.conf` system-features |
| **Debugging** | Can't run the output. Must use QEMU or transfer to hardware. | `file`, `ldd`, run directly. Full debugging. |

The key insight: **start native, finish cross**. Native builds find real
s390x-specific issues (assembler compatibility, SIMD, endianness) without the
noise of cross-compilation wrapper problems. Once a native binary works, the
cross-compilation fixes have a known-good baseline to test against.

### Phase 1: Native build on s390x hardware

Build ClickHouse natively on s390x (e.g., LinuxONE Community Cloud):

```bash
cd ~/nixpkgs
nix-build -A clickhouse --cores 2 -j 1
```

The `broken` flag doesn't apply (`buildPlatform == hostPlatform`). With
`gcc.arch = "z15"` set globally, all packages build with z15-optimized code.

**Issues found and fixed during Phase 1:**

1. **zlib VX CRC32** — `zlib/default.nix`: added `-march=z13` to `NIX_CFLAGS_COMPILE`
2. **OpenSSL Keccak assembly** — `openssl/default.nix`: added `CFLAGS=-march=${gcc.arch or "z10"}`
3. **PCRE2 JIT** — `pcre2/default.nix`: re-enabled JIT (SLJIT has s390x backend since 10.39)
4. **nix system-features** — `/etc/nix/nix.conf`: added `gccarch-z15`

All were pre-existing nixpkgs gaps, not ClickHouse-specific. Each fix benefits
every s390x package, not just ClickHouse.

### Phase 2: Fix any remaining native build issues

The native build is currently progressing through the bootstrap chain. Expected
issues: memory pressure during ClickHouse's link step (4GB RAM, may need swap),
x86 assumptions in some of ClickHouse's 150+ bundled contrib libraries.

### Phase 3: Selective unbundling for hardware accel (Strategy C)

Once the base build works, replace high-value bundled libraries with nixpkgs
versions that have s390x hardware acceleration:

1. **OpenSSL** — use nixpkgs openssl with CPACF (already patched in our local nixpkgs)
2. **zlib** — DFLTCC hardware deflate. Note: upstream zlib 1.3.2 does NOT include
   DFLTCC support ([PR #410](https://github.com/madler/zlib/pull/410) was never merged).
   Would need either carrying IBM's patch or switching to
   [zlib-ng](https://github.com/zlib-ng/zlib-ng) (as Fedora has done).
3. **ICU** — use nixpkgs icu (avoids the endianness patch hack)

### Phase 4: Return to cross-compilation

With a known-good native binary as baseline, fix the remaining cross-compilation
issues:
1. Use `buildPackages.llvmPackages_21.clang-unwrapped` for the sub-cmake native compiler
2. Verify the cross-built binary matches the native binary's behavior
3. Upstream the fixes

### Phase 5: Upstream

1. Submit the nixpkgs expression changes as a PR
2. File upstream ClickHouse issues for the Nix-unfriendly patterns (unprefixed
   tool search, `execute_process` without inheriting cache vars)
3. Document the patterns for other complex C++ packages

### Phase 6: Rebuild nix for z15

The nix binary installed on s390x was compiled during bootstrap with `-march=z900`.
While functional, it would benefit from z15 optimization:
- **SHA-256** (NAR hashing) — z15's CPACF accelerates SHA in hardware
- **SQLite** (nix store) — z15 VXE3 SIMD for string operations
- **Compression** (NAR packing) — z15 DFLTCC for hardware deflate

After the bootstrap completes, rebuild nix itself:
```bash
nix-build -A nix --cores 2 -j 1
# Then install the z15-optimized nix
```

## Applicability to Other Packages

The patterns here apply to any project that vendors its own toolchain:

| Pattern | Also seen in |
|---------|-------------|
| Vendored sysroot/compiler-rt | Chromium, Android NDK |
| `execute_process` sub-cmake | LLVM, Qt, KDE |
| Unprefixed tool search | Many cmake projects |
| Hermetic-vs-hermetic conflict | Bazel projects (TensorFlow, Envoy, Redpanda) |

The general lesson: when two hermetic build systems collide, the fix is either
to fully replace one (Strategy A) or to inject the missing pieces at the seams
(Strategy B). Strategy C picks the high-value seams.

---

*Part of the [S390X Nixpkgs Porting Guide](../S390X-PORTING-GUIDE.md). See also:
[ClickHouse Case Study](example-clickhouse.md) | [Patch Reuse Strategy](ibm-z-patch-reuse.md)*
