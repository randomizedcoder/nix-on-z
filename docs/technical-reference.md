# s390x Technical Reference

[Back to overview](../S390X-PORTING-GUIDE.md)

---

Quick-reference for Nix packagers encountering s390x-specific build issues.

## Architecture Summary

| Property | Value |
|----------|-------|
| System triple | `s390x-unknown-linux-gnu` |
| Byte order | **Big-endian** |
| Word size | 64-bit |
| Dynamic linker | `/lib/ld64.so.1` |
| Page sizes | 4 KB (default), 1 MB (hugepages) |
| GOARCH | `s390x` |
| Rust target | `s390x-unknown-linux-gnu` |
| Node.js arch | `s390x` |
| Python platform | `linux-s390x` |
| Debian arch | `s390x` |
| GCC `-march` | `z13`, `z14`, `z15`, `z16` (arch13-arch14) |

## Machine Types and Architecture Levels

IBM Z hardware is identified by a machine type number in `/proc/cpuinfo`. Each generation
adds instructions and hardware features that GCC can exploit via `-march=`.

| Machine type | Name | Year | GCC `-march` | Key features enabled |
|-------------|------|------|-------------|---------------------|
| 2964, 2965 | z13 | 2015 | `z13` | Vector Extension Facility (VXE), SIMD |
| 3906, 3907 | z14 | 2017 | `z14` | VXE2, miscellaneous instruction extensions 2 |
| 8561, 8562 | z15 | 2019 | `z15` | VXE3, DFLTCC (hardware deflate), enhanced sort |
| 3931, 3932 | z16 | 2022 | `z16` | NNPA (AI accelerator), bear enhancements |
| 9175 | z17 | 2025 | `arch15` | Requires GCC 15+ |

**Check your hardware:** `grep 'machine' /proc/cpuinfo`

**In nixpkgs**, the architecture level is set in `lib/systems/examples.nix` via `gcc.arch`.
This value propagates to all packages — it controls `-march=` for GCC, the assembler
instruction set, and hardware feature enablement (e.g., DFLTCC for zlib, CPACF for OpenSSL).

The default is `z13` (safe for all modern hardware). If your hardware is newer, raise it
for better performance:

```nix
# In lib/systems/examples.nix or your flake's crossSystem:
s390x = {
  config = "s390x-unknown-linux-gnu";
  gcc.arch = "z15";  # match your hardware
};
```

**Detect automatically:** `nix run .#check-arch` compares your hardware against the
configured `gcc.arch` and recommends the optimal setting.

**Important: system-features requirement.** When `gcc.arch` is set, nixpkgs adds
`gccarch-<arch>` as a required system feature on derivations. The nix daemon must
advertise this feature or all builds fail with "missing system features". Add to
`/etc/nix/nix.conf`:

```
system-features = benchmark big-parallel gccarch-z15 nixos-test uid-range
```

Then restart the nix-daemon (`sudo systemctl restart nix-daemon`).

For **native builds** (not cross), `gcc.arch` is set in `lib/systems/platforms.nix`
under `s390x-multiplatform`. For **cross-compilation**, it's set in
`lib/systems/examples.nix` or in the flake's `crossSystem`.

## Endianness

**This is the #1 source of s390x build failures.**

s390x is big-endian, while x86_64 and aarch64 are little-endian. Common symptoms:

- **Byte-swapped data**: Serialization/deserialization code that assumes little-endian
- **Hardcoded byte order**: `#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__` paths missing BE alternative
- **Test failures**: Tests with hardcoded little-endian expected values
- **Binary file parsing**: ELF, protocol buffers, image formats with byte-order assumptions

**Nix detection patterns:**
```nix
# In a package derivation:
stdenv.hostPlatform.isBigEndian       # true on s390x
stdenv.hostPlatform.isLittleEndian    # false on s390x

# In a meta block:
badPlatforms = lib.platforms.bigEndian;  # exclude all BE platforms
```

**C/C++ detection:**
```c
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
  // big-endian path (s390x)
#elif __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  // little-endian path (x86_64, aarch64)
#endif
```

**Common fix pattern** from linux-on-ibm-z: add `htole32()`/`le32toh()` calls around data
that crosses byte-order boundaries, or use `__builtin_bswap32()`/`__builtin_bswap64()`.

## SIMD / Vector Extension Facility

s390x has its own SIMD: the **Vector Extension Facility (VXE)**, introduced with z13.
It is *not* SSE/AVX compatible.

| x86_64 | s390x Equivalent | Notes |
|--------|------------------|-------|
| SSE/SSE2 | VX (z13) | 128-bit vectors, different intrinsics |
| AVX/AVX2 | VXE (z14) | Extended vector instructions |
| AVX-512 | NNPA (z16) | Neural network processing assist |
| `<immintrin.h>` | `<vecintrin.h>` | Completely different API |

**Impact on Nix packages:**
- Code using `#include <immintrin.h>` or `__m128i` types will **not compile**
- Many packages have x86 SIMD optimizations with no s390x equivalent
- Some packages (openssl, boringssl, zlib) already have s390x vector paths

**Common fix:** Disable SIMD or provide a scalar fallback:
```nix
configureFlags = lib.optionals stdenv.hostPlatform.isS390x [
  "--disable-sse" "--disable-avx"
];
```

## JIT Compilation

s390x has a different instruction set, so any JIT compiler that generates machine code needs
an s390x backend. Many JIT engines lack this.

**Known JIT status on s390x:**

| JIT Engine | s390x Support | Notes |
|------------|---------------|-------|
| LLVM | Yes | Full backend since LLVM 3.x |
| GCC JIT (libgccjit) | Yes | Via GCC s390x backend |
| PCRE2 JIT | **No** — uses SLJIT | Disabled in nixpkgs: `--enable-jit=no` |
| LuaJIT | **No** | linux-on-ibm-z has a port (sljit-based) |
| JavaScriptCore (WebKit) | **No** | No s390x backend |
| V8 (Node.js/Chrome) | **Yes** | IBM maintains s390x backend |
| OpenJDK JIT (C2) | **Yes** | IBM contributes s390x JIT |
| SLJIT | **Partial** | linux-on-ibm-z has s390x port |

**nixpkgs example** — PCRE2 disables JIT on s390x:
```nix
# pcre2/default.nix:26
"--enable-jit=${if stdenv.hostPlatform.isS390x then "no" else "auto"}"
```

## Seccomp & Syscalls

s390x uses different syscall numbers than x86_64. Any seccomp filter or syscall whitelist
that hardcodes syscall numbers will break.

**Key differences:**
- Syscall numbers are completely different (not just offset — different mapping)
- `AUDIT_ARCH_S390X = 0x80000016` (vs `AUDIT_ARCH_X86_64 = 0xC000003E`)
- `SCMP_ARCH_S390X` in libseccomp

**Real example from nix-on-z bootstrap:**
The Nix daemon's seccomp sandbox needed patching to include s390x syscall numbers.
The `prctl` and `clone3` syscalls have different numbers, and the seccomp BPF programs
must reference the correct architecture constant.

**Common fix patterns:**
- Use `libseccomp` instead of raw BPF — it handles arch differences
- Use symbolic syscall names (`SYS_read`) not numbers (`0` on x86_64, `3` on s390x)
- Test seccomp filters under QEMU s390x emulation

## Frame Pointer

GCC on s390x has a specific frame pointer issue tracked in
[Launchpad bug 2064538](https://bugs.launchpad.net/ubuntu/+source/gcc-14/+bug/2064538).

**In nixpkgs**, the cc-wrapper (line ~854) has s390x-specific handling:
- The `-fno-omit-frame-pointer` flag can cause issues on s390x
- Some packages need explicit frame pointer configuration

This is a less common issue but can cause subtle runtime crashes or debugger failures.

## GCC Specifics

s390x GCC configuration has several differences from x86:

**`--with-cpu` excluded:**
Unlike x86 where `--with-cpu=<baseline>` is commonly set, the s390x GCC build in nixpkgs
does not set this flag — the default (z900 baseline for s390x) is used.

**crti/crtn stubs:**
s390x uses different C runtime initialization files. The crti.o and crtn.o stubs follow
the s390x ABI, which differs from the x86_64 SysV ABI. Packages that link these explicitly
or reference them by path may need adjustment.

**Arch-specific GCC flags:**
```
-march=z13       # Minimum for vector extensions (VX)
-march=z14       # VXE (enhanced vector)
-march=z15       # Miscellaneous instruction extensions
-march=z16       # NNPA (neural network), BEAR enhancement
-mtune=z16       # Tune for latest hardware
-mvx              # Enable vector extensions explicitly
-mzvector         # Enable vector built-in functions
```

## Architecture Quick Reference Card

```
┌────────────────────────────────────────────┐
│           s390x (IBM Z) Quick Reference    │
├─────────────────┬──────────────────────────┤
│ Full name       │ IBM System/390x (64-bit) │
│ Endianness      │ Big-endian               │
│ Word size       │ 64-bit                   │
│ Page size       │ 4 KB (default)           │
│ Hugepage        │ 1 MB                     │
│ Registers (GPR) │ 16 x 64-bit             │
│ Registers (FPR) │ 16 x 64-bit             │
│ Vector regs     │ 32 x 128-bit (VX, z13+) │
│ Addressing      │ 64-bit virtual           │
│ Instruction set │ Variable length (2/4/6B) │
│ Alignment       │ Relaxed (no SIGBUS)      │
│ Atomics         │ Compare-and-swap (CS/CSG)│
├─────────────────┼──────────────────────────┤
│ System triple   │ s390x-unknown-linux-gnu  │
│ Dynamic linker  │ /lib/ld64.so.1           │
│ AUDIT_ARCH      │ 0x80000016               │
│ ELF machine     │ EM_S390 (22)             │
│ Nix predicate   │ isS390x                  │
│ Nix platform    │ s390x-linux              │
│ GOARCH          │ s390x                    │
│ Rust target     │ s390x-unknown-linux-gnu  │
│ Debian arch     │ s390x                    │
│ Docker platform │ linux/s390x              │
├─────────────────┼──────────────────────────┤
│ z13 (2015)      │ VX: 128-bit SIMD         │
│ z14 (2017)      │ VXE: enhanced vectors    │
│ z15 (2019)      │ Misc instruction ext.    │
│ z16 (2022)      │ NNPA, BEAR, SORT         │
│ z17 (2025)      │ AI accelerator           │
└─────────────────┴──────────────────────────┘
```

## Hardware Crypto Acceleration

s390x has **CPACF** (CP Assist for Cryptographic Functions) built into every processor:

| Function | Instruction | Benefit |
|----------|-------------|---------|
| AES | KM/KMC | Hardware AES encryption |
| SHA | KIMD/KLMD | Hardware SHA-1/256/512 |
| DES/TDES | KM/KMC | Hardware DES |
| Random | TRNG | True hardware RNG |

OpenSSL and GnuTLS can use these via the `s390x` engine. Nix's openssl package should
enable the s390x-specific `CPACF` code paths.

**Python benefit:** CPython's `hashlib` uses OpenSSL, so `hashlib.sha256()` etc.
automatically use CPACF hardware acceleration — ~20% faster hash operations.

## Hardware Compression

s390x z15+ has **DFLTCC** (Deflate Conversion Call) for hardware zlib/gzip compression:

- 10-50x faster than software deflate
- Supported in upstream zlib-ng and zlib (with patches)
- nixpkgs `zlib` should enable DFLTCC when targeting z15+

**Python benefit:** CPython's `zlib` and `gzip` modules link against system zlib.
If zlib has DFLTCC, `gzip.compress()` / `zlib.compress()` get 10-50x hardware speedup.
Currently blocked — upstream zlib 1.3.2 doesn't include DFLTCC (see TODO below).

## Python on s390x

**nixpkgs default:** `python3` = Python 3.13. Versions 3.11–3.15 are available.

**TODO:** The ClickHouse build currently uses Python 3.13 (the nixpkgs default).
Python 3.14 adds stdlib `zstd` support and Python 3.15 is available in nixpkgs.
Upgrade ClickHouse (and the default) to 3.14+ once the s390x native build is
validated on 3.13.

CPython builds and runs on s390x, but several optimization opportunities are missing
in nixpkgs today.

### What works automatically

| Feature | Mechanism | Benefit |
|---------|-----------|---------|
| CPACF crypto | `hashlib` → OpenSSL → CPACF hardware | ~20% faster hashing |
| VXE string ops | glibc compiled with `-march=z15` vectorizes `memcpy`, `strcmp`, etc. | ~10-20% string ops |
| `-march=z15` codegen | GCC generates z15-specific instructions | ~5% baseline improvement |

These are free when `gcc.arch = "z15"` is set globally (already done in nix-on-z).

### TODO: Enable PGO + LTO for CPython

CPython supports Profile-Guided Optimization (`--enable-optimizations`) and Link-Time
Optimization (`--with-lto`). This runs the test suite during build to collect profiling
data, then recompiles with optimized branch prediction and inlining. Expected: **5-15%
overall speedup**.

nixpkgs does not currently enable this for s390x. The fix is straightforward:

```nix
# In pkgs/development/interpreters/python/cpython/default.nix:
configureFlags = [
  "--enable-optimizations"  # PGO
  "--with-lto"              # LTO
];
```

**Trade-off:** Build time increases significantly (runs test suite twice). Worth it for
the final package but slows down iteration during porting.

### TODO: Switch to zlib-ng for DFLTCC

Upstream zlib 1.3.2 does not include DFLTCC support (IBM's PR
[madler/zlib#410](https://github.com/madler/zlib/pull/410) is unmerged). The
[zlib-ng](https://github.com/zlib-ng/zlib-ng) project has full DFLTCC support.

Switching Python (and all 95 zlib-dependent packages) to zlib-ng would unlock
10-50x hardware compression on z15+. This is a nixpkgs-wide change, not
Python-specific.

### PEP 744: JIT compilation — NOT available on s390x

Python 3.13 introduced an experimental JIT compiler via
[PEP 744](https://peps.python.org/pep-0744/) using a "copy-and-patch" technique.
**It does not support s390x.** Supported architectures: x86_64, aarch64 only.

The copy-and-patch JIT requires pre-built machine code templates for each target
architecture. s390x's variable-length instruction encoding (2/4/6 bytes) differs
fundamentally from x86/ARM, making a backend non-trivial. There is no known effort
to add s390x support.

**Impact:** CPython on s390x will continue to use the interpreter. For
performance-critical Python workloads on s390x, alternatives include:

- **PyPy**: Has s390x JIT support via RPython (IBM contributed the backend)
- **Cython/Numba**: Compile hot loops to native code via GCC/LLVM (both have s390x backends)
- **C extensions**: Performance-critical code already in C/C++ is unaffected

This is a notable platform gap — x86_64 and aarch64 Python users will get 10-30%
JIT speedups that s390x users cannot access. Worth tracking upstream CPython
development for future s390x JIT backend support.

## Perl on s390x

Perl builds and runs on s390x without patches. IBM uses Perl extensively on Z —
the linux-on-ibm-z organization has no dedicated Perl repo because it just works.
No nixpkgs changes are needed for correctness.

### What works automatically

| Feature | Mechanism | Benefit |
|---------|-----------|---------|
| `-march=z15` codegen | Global `gcc.arch` propagates to Perl build | Faster string/memory ops via vectorized glibc |
| Compress::Zlib | Uses system zlib | Would get DFLTCC for free if zlib-ng is adopted |
| Threading | `-Dusethreads` enabled unconditionally | Works on s390x |

### What doesn't help (unlike Python)

- **Digest::SHA / Digest::MD5** — These are pure C implementations bundled with
  Perl core. They do **not** use OpenSSL, so CPACF hardware crypto is not leveraged.
  Switching to OpenSSL's EVP interface would require upstream Perl changes.
- **PGO / LTO** — Perl's `Configure` doesn't have a clean PGO path like CPython's
  `--enable-optimizations`. Technically possible via `-Doptimize="-O3 -flto"` but
  not well-tested and can break XS module linking.
- **Regex JIT** — Perl's built-in regex engine is bytecode-interpreted with no JIT.
  The optional `re::engine::PCRE2` CPAN module could use PCRE2's SLJIT s390x
  backend (which we've re-enabled), but this requires per-application module changes.

### Summary

Perl on s390x is a "just works" story. The main performance gains come from
dependency-level improvements (zlib DFLTCC, glibc vectorization) rather than
Perl-specific changes. No TODO items — Perl benefits automatically from the
global `gcc.arch = "z15"` setting.

## Compilation Performance on z15

The z15 has architectural advantages that make it surprisingly good at
compilation workloads, even compared to high-end x86 servers.

### Why compilers run well on z

| Feature | z15 | Typical x86 (Xeon) | Impact on compilation |
|---------|-----|---------------------|----------------------|
| **Clock speed** | 5.2 GHz sustained | 3.0-4.0 GHz (turbo burst) | Compilation is heavily single-threaded; z15's sustained clock wins |
| **L1 cache** | 128KB I + 128KB D per core | 32-64KB I + 32-48KB D | 2-4x more L1 — huge for compiler symbol tables and ASTs |
| **L2 cache** | 4MB per core | 1-1.25MB per core | 3-4x more L2 — keeps more of the working set close |
| **Branch prediction** | z15 has one of the best branch predictors in any CPU | Good, but optimized for throughput | Compilers are branch-heavy (if/switch on AST node types); z15 excels |
| **Pipeline width** | Up to 6 instructions/cycle decoded | 4-6 instructions/cycle | Comparable, but z15's pipeline is optimized for branch-heavy code |
| **Out-of-order depth** | Very deep reorder buffer | Deep | Both good; z15's is tuned for commercial/compiler-style workloads |

### Memory and I/O architecture advantages

z15's memory subsystem was designed for virtual machine workloads, which
gives it unique advantages for memory-intensive builds:

- **Channel-based I/O** — z uses dedicated I/O channel processors, not
  CPU-driven DMA. Disk I/O (including swap) happens independently of the
  CPU — the processor doesn't stall waiting for I/O completion.
- **PAV (Parallel Access Volumes)** — Multiple concurrent I/O operations
  to the same disk. Swap reads/writes overlap, reducing latency.
- **DAT (Dynamic Address Translation)** — z has had hardware virtual memory
  since the 1970s (before x86 existed). The page table walker is deeply
  optimized — TLB misses are faster to resolve than on x86.
- **CMMA (Collaborative Memory Management Assist)** — The z15 hypervisor
  and guest OS share page state information, so the hypervisor makes smarter
  decisions about which pages to steal when memory is tight.
- **Hardware page management** — Page-in/page-out is handled by dedicated
  hardware, not by general-purpose CPU instructions.

### Swap is less painful on z

On x86, swapping during a build is usually catastrophic — the CPU stalls
on page faults while DMA transfers complete. On z, the architecture
mitigates this:

1. **Channel subsystem handles I/O independently** — the CPU continues
   executing other threads/processes while pages are fetched
2. **Hardware page fault handling** is faster than x86's microcode-based
   approach
3. **CMMA** means the hypervisor pre-stages likely-needed pages before
   the guest even faults

**Observed during ClickHouse build (z15, 2 vCPU, 4GB RAM):**
With 95% RAM used and 173MB in swap, `vmstat` showed `si=0, so=0` on
active samples — the swapped pages were cold (unused Python modules, GCC
data structures) and the CPU stayed at 96% user with zero I/O wait. On
x86 with the same memory pressure, you'd typically see 5-15% `wa` (I/O
wait) stealing CPU time.

**Practical guidance:** Don't fear swap on z. A 4GB swap file on a 4GB
machine is fine for most builds. The real risk is LLVM/Clang linking, where
a single `ld` process can spike to 8GB+ — at that point even z's hardware
can't hide the latency. For large link steps, consider `--param
ggc-min-expand=0` to reduce GCC's memory usage, or increase swap to 8GB.

### Transparent Huge Pages for compilers

s390x hugepages are **1MB** (vs 2MB on x86). GCC/LLVM working sets (ASTs,
symbol tables, IR) can be hundreds of MB — with 4KB pages that's tens of
thousands of TLB entries. With 1MB hugepages, it's just hundreds.

By default Ubuntu sets THP to `madvise` (opt-in only). GCC doesn't call
`madvise(MADV_HUGEPAGE)`, so it gets zero hugepages. Setting THP to `always`
lets the kernel automatically promote large allocations:

```bash
echo always > /sys/kernel/mm/transparent_hugepage/enabled
```

**Observed:** After enabling THP during the LLVM build (4806 files), the kernel
immediately promoted 478MB of compiler allocations to 1MB hugepages — ~478 TLB
entries instead of ~122,000. This is included in the tuning tool (`nix run
.#tune-ubuntu`).

### What doesn't help compilation speed

- **Vector extensions (VXE)** — Compilers don't use SIMD internally.
  VX/VXE generates better code for *output* programs but doesn't speed up
  the compiler itself.
- **CPACF crypto** — Not relevant for compilation (speeds up hashing/signing
  in OpenSSL, not GCC).
- **DFLTCC compression** — Doesn't help during compilation (helps with
  compressing build artifacts and nix store paths afterward).

## Multi-LPAR Distributed Nix Builds

This section describes the vision for scaling nix builds across multiple
LPARs on the same IBM Z system — leveraging z-specific hardware features
that have no equivalent on x86.

### The opportunity

A single z15/z16 CEC (Central Electronics Complex) can host dozens of LPARs
(Logical Partitions), each running its own Linux instance. Unlike VMs on x86
(which share a host OS), LPARs are hardware-isolated by PR/SM (Processor
Resource/Systems Manager) — the z hypervisor that runs in firmware, not software.

Nix already supports **distributed builds** via `nix.buildMachines`, where a
coordinator delegates derivations to remote builders over SSH. On x86 this means
network I/O (1-25 Gbps Ethernet). On z, the LPARs can communicate via
**Hipersockets** — and that changes everything.

### Hipersockets: memory-speed inter-LPAR communication

Hipersockets is a z hardware feature that provides memory-to-memory networking
between LPARs on the same CEC. There is no physical NIC, no cable, no switch.
The hypervisor maps a shared memory region between partitions and mediates access.

| Property | Hipersockets | 25GbE Ethernet | InfiniBand EDR |
|----------|-------------|----------------|----------------|
| **Latency** | <1 μs (memory copy) | 5-25 μs | 1-2 μs |
| **Bandwidth** | Memory bus speed (~100+ GB/s) | 3.1 GB/s | 12.5 GB/s |
| **CPU overhead** | Near zero (no DMA, no interrupt coalescing) | Significant (driver, stack, interrupts) | Moderate (RDMA helps) |
| **Physical hardware** | None (firmware) | NICs, cables, switches | HCAs, cables, switches |
| **Configuration** | z/VM or LPAR definition | OS network stack | Subnet manager, drivers |
| **Isolation** | PR/SM hardware isolation | VLANs (software) | Partitioning (software) |

For nix builds, the key metric is **store path transfer speed**. When a builder
finishes a derivation, the result must be copied back to the coordinator via
`nix copy`. A typical derivation output is 1-100MB. At memory bus speed, even a
100MB result transfers in under a millisecond. On 25GbE, the same transfer takes
30ms+ with TCP overhead.

### Architecture: Nix build cluster on a single z CEC

```
┌─────────────────────────────────────────────────────────┐
│                    IBM z15/z16 CEC                       │
│                                                         │
│  ┌─────────────┐  Hipersockets   ┌─────────────┐       │
│  │  LPAR 1     │◄──────────────►│  LPAR 2     │       │
│  │  Coordinator│  <1μs latency   │  Builder A  │       │
│  │  4 vCPU     │                 │  4 vCPU     │       │
│  │  nix-daemon │                 │  nix-daemon │       │
│  │  16GB RAM   │                 │  16GB RAM   │       │
│  └──────┬──────┘                 └─────────────┘       │
│         │ Hipersockets                                  │
│  ┌──────┴──────┐  Hipersockets   ┌─────────────┐       │
│  │  LPAR 3     │◄──────────────►│  LPAR 4     │       │
│  │  Builder B  │  <1μs latency   │  Builder C  │       │
│  │  4 vCPU     │                 │  4 vCPU     │       │
│  │  nix-daemon │                 │  nix-daemon │       │
│  │  16GB RAM   │                 │  16GB RAM   │       │
│  └─────────────┘                 └─────────────┘       │
│                                                         │
│  Total: 16 vCPUs, 64GB RAM, memory-speed interconnect  │
└─────────────────────────────────────────────────────────┘
```

**Coordinator (LPAR 1)** runs `nix-build` and delegates derivations to builders.
Nix's job scheduler sends independent derivations to different LPARs in parallel.

**Builders (LPARs 2-4)** run `nix-daemon` and accept remote builds via SSH.
Each has its own nix store, CPU, and RAM — fully isolated.

**Hipersockets** connects all LPARs at memory speed. Store path transfers
(the main bottleneck in distributed nix builds on x86) become negligible.

### Nix configuration

On the coordinator LPAR:

```nix
# /etc/nix/nix.conf
builders = ssh://lpar2 s390x-linux - 4 1 big-parallel,gccarch-z15 ; \
           ssh://lpar3 s390x-linux - 4 1 big-parallel,gccarch-z15 ; \
           ssh://lpar4 s390x-linux - 4 1 big-parallel,gccarch-z15
max-jobs = 0  # delegate everything to remote builders
builders-use-substitutes = true
```

On each builder LPAR:

```nix
# /etc/nix/nix.conf
max-jobs = 4
cores = 4
system-features = benchmark big-parallel gccarch-z15 nixos-test
```

SSH keys are distributed so the coordinator can connect to builders without
passwords. With Hipersockets, the SSH connections are over the internal
memory-mapped network — no external network needed.

### Why this is better than x86 build farms

| Aspect | x86 build farm | z multi-LPAR |
|--------|---------------|-------------|
| **Interconnect** | 1-25 Gbps Ethernet (5-25μs latency) | Hipersockets (<1μs, memory bus bandwidth) |
| **Store path transfer** | Network bottleneck — large closures take seconds | Sub-millisecond — memory copy |
| **Isolation** | VMs or containers (software) | PR/SM hardware partitioning (EAL5+ certified) |
| **Failure domain** | Multiple servers, switches, power supplies | Single CEC — but LPARs are independently restartable |
| **Scaling up** | Buy more servers, more switches, more cables | Add LPARs — no hardware changes |
| **Scheduling overhead** | Nix SSH + TCP + serialization per derivation | Nix SSH + memory copy — TCP overhead nearly eliminated |
| **Cache coherence** | No shared cache between machines | LPARs share L3/L4 cache on same CEC — warm cache effects |
| **Power & cooling** | N servers × per-server overhead | Single system — dramatically better power/build ratio |

### The ClickHouse example

Our ClickHouse build has ~385 derivations and takes hours on 2 vCPUs. The LLVM
component alone is 4806 files. On a 4-LPAR cluster:

- **Parallelism:** 4 independent derivations building simultaneously (one per LPAR)
- **Within each derivation:** 4 cores for `make -j4` (vs our current `-j1 --cores 2`)
- **Memory:** 16GB per LPAR — no swap needed, no OOM risk, no memory pressure
- **Transfer:** Completed derivations move between LPARs at memory speed
- **Estimate:** The build that takes 8+ hours on 2 cores / 4GB could complete in
  under 1 hour on 16 cores / 64GB with memory-speed interconnect

### Shared nix store via z/VM minidisks

An alternative to copying store paths is **shared storage**. z/VM supports
shared minidisks (ECKD DASD volumes visible to multiple guests). If all LPARs
mount the same nix store:

- **No store path copying needed** — builders write directly to the shared store
- **Instant availability** — as soon as a builder finishes, the result is visible
  to all other builders and the coordinator
- **Single binary cache** — no duplication across LPARs
- **Locking required** — nix's SQLite database would need careful handling
  (possibly one writer, multiple readers)

This is similar to NFS-shared nix stores on x86, but with **hardware-backed
shared storage** instead of network filesystem overhead. The z/VM minidisk I/O
goes through the channel subsystem, not a network stack.

### Cross-LPAR cache warming

Another z-specific advantage: LPARs on the same CEC share the **L3 and L4 caches**.
When LPAR 1 reads a nix store path that LPAR 2 recently wrote, there's a chance
it's still warm in the shared cache hierarchy. On x86, two separate servers have
completely cold caches relative to each other.

This matters for nix because builds frequently read outputs of other builds
(header files, libraries, pkg-config files). Cache warming effects compound
across the dependency graph.

### What IBM would need to provide

To make this a reality for the nix community:

1. **LinuxONE Community Cloud multi-LPAR access** — Currently the community cloud
   gives one VM per user. A build cluster needs 3-4 LPARs with Hipersockets between them.
2. **Sufficient resources per LPAR** — At least 4 vCPUs and 16GB RAM per LPAR for
   comfortable builds (current community cloud offers 2 vCPU / 4GB).
3. **Shared DASD** — Optional but ideal for a shared nix store.
4. **Persistent allocation** — Build clusters need uptime for cache warming.
   The current community cloud has 120-day time limits.

### What the Nix team would need to provide

1. **s390x in the installer** — See [Nix Installer Platforms](nix-installer-platforms.md)
   for our proposed patches.
2. **s390x Hydra builders** — To populate the official binary cache. A multi-LPAR
   setup on donated z hardware would be the most efficient way to run this.
3. **s390x in the CI matrix** — nixpkgs PRs should test s390x to prevent regressions.

### The pitch

> **One IBM z16 CEC running 4 LPARs with Hipersockets could serve as the entire
> s390x Hydra build infrastructure for nixpkgs — replacing what would otherwise
> be a rack of x86 servers with network switches.** The memory-speed interconnect
> eliminates the main bottleneck in distributed Nix builds (store path transfer),
> and PR/SM hardware isolation provides better security than any software
> virtualization. A single machine, zero network infrastructure, EAL5+ security,
> and faster builds than a comparable x86 cluster.
