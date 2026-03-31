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

## Hardware Compression

s390x z15+ has **DFLTCC** (Deflate Conversion Call) for hardware zlib/gzip compression:

- 10-50x faster than software deflate
- Supported in upstream zlib-ng and zlib (with patches)
- nixpkgs `zlib` should enable DFLTCC when targeting z15+
