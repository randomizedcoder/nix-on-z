[< Back to README](../README.md)

# s390x Analysis

## Endianness Analysis

s390x is big-endian, which is the most common source of porting issues across
the [linux-on-ibm-z](https://github.com/orgs/linux-on-ibm-z/repositories)
ecosystem. We investigated Nix's binary serialization layer -- the worker
protocol -- to determine if endianness is a concern.

**Result: Nix's worker protocol is endian-safe.** All integer serialization
explicitly uses little-endian wire format, regardless of host byte order.

The write path in `src/libutil/include/nix/util/serialise.hh` manually
decomposes integers into little-endian bytes:

```cpp
inline Sink & operator<<(Sink & sink, uint64_t n)
{
    unsigned char buf[8];
    buf[0] = n & 0xff;
    buf[1] = (n >> 8) & 0xff;
    buf[2] = (n >> 16) & 0xff;
    buf[3] = (n >> 24) & 0xff;
    buf[4] = (n >> 32) & 0xff;
    buf[5] = (n >> 40) & 0xff;
    buf[6] = (n >> 48) & 0xff;
    buf[7] = (unsigned char) (n >> 56) & 0xff;
    sink({(char *) buf, sizeof(buf)});
    return sink;
}
```

The read path in `readNum<T>()` (same file) uses `readLittleEndian<uint64_t>()`
from `src/libutil/include/nix/util/util.hh`:

```cpp
template<typename T>
T readLittleEndian(unsigned char * p)
{
    T x = 0;
    for (size_t i = 0; i < sizeof(x); ++i)
        x |= ((T) p[i]) << (i * 8);
    return x;
}
```

This means the binary characterization test data files (`.bin` files under
`src/libstore-tests/data/worker-protocol/`) -- which were generated on x86_64 --
are valid on s390x without modification. No endianness patches are needed for
the Nix package manager itself.

## s390x Porting Patterns (from IBM linux-on-ibm-z)

IBM maintains the [linux-on-ibm-z](https://github.com/orgs/linux-on-ibm-z/repositories)
GitHub organization with patches and build scripts for hundreds of open-source
projects on s390x. Studying their work reveals common porting patterns that we
expect to encounter as we take Nix and nixpkgs deeper on this architecture.

### 1. Endianness (big-endian) -- the most common issue

s390x is **big-endian**, unique among modern Linux server architectures. This
affects nearly every C/C++ project that does binary I/O:

- **Byte-swap operations reversed**: Functions that assume little-endian native
  byte order need `#if __BYTE_ORDER == __BIG_ENDIAN` guards
- **Wire protocol assumptions**: Network and serialization code that assumes
  host byte order = little-endian
- **Struct padding / memory layout**: Smaller types read from larger buffers at
  wrong byte offsets
- **Database serialization**: Optimized read paths gated on
  `__ORDER_LITTLE_ENDIAN__` that must be adapted

### 2. Architecture detection

Many projects don't recognize `s390x` or `__s390x__` as a valid target:

- Missing `#elif defined(__s390x__)` in platform detection `#ifdef` chains
- Architecture name strings not matching (e.g., cmake/meson target triples)
- Feature macros like `OPTIMIZED_*_AVAILABLE` only defined for x86_64/aarch64

We already have this in [Patch 1](patches/0001-add-s390x-support.md) (`__s390x__` for stack pointer and seccomp).

### 3. Type mismatch / strict type casting

GCC on s390x is stricter about type conversions, especially on big-endian:

- `reinterpret_cast<int*>(&size_t_var)` -- on little-endian the int is at the
  start of the size_t; on big-endian it reads the wrong half
- `void *` pointer arithmetic errors (`-Werror=pointer-arith`)

### 4. Atomic operations

- Missing platform-specific compare-and-swap implementations
- GCC on s390x doesn't always inline atomic operations -- needs `-latomic`

### 5. Linker and toolchain

- LLD has incomplete s390x support; must use `ld.bfd` instead
- GCC version requirements differ (e.g., Z15 vector support needs GCC >= 9)

### 6. Test timeouts

s390x machines (especially shared/emulated) are slower than x86_64. Test
timeouts often need 5-10x increases. We handle this with `-t 10` in our test
runner.

### 7. Missing pre-built binaries

Many projects provide pre-built binaries for x86_64 and aarch64 but not s390x.
This is the fundamental reason this project exists -- nixpkgs doesn't have s390x
binary caches, so everything must build from source.

### 8. SIMD / hardware-specific instruction gating

x86 intrinsics (SSE, AVX, CLMUL, etc.) need `#ifdef` guards. s390x has its own
vector extensions (z13+) but most open-source code doesn't use them yet.

## Hardware Capabilities (Unused by nixpkgs)

s390x has 25 years of hardware evolution beyond the base z900 ISA, but nixpkgs
targets the z900 baseline — missing every hardware acceleration feature. This
section documents what's available and what we've found unused.

### Current nixpkgs state (as of 2026-03)

| Area | Status | Impact |
|------|--------|--------|
| `gcc.arch` | **Not set** (defaults to z900, year 2000) | No vector extensions, no modern ISA |
| Vector extensions (SIMD) | **Disabled** | zlib CRC32 cross-compile fails |
| DFLTCC (hardware deflate) | **Zero references** in all of nixpkgs | z15+ hardware compression unused |
| OpenSSL CPACF | **Falls through to generic64** when cross-compiling | Hardware AES/SHA unused |
| Platform definition | **Missing** from `platforms.nix` | No linux-kernel config for s390x |
| Binary cache | **Empty** — no s390x packages cached | Everything builds from source |

### s390x hardware timeline

| Generation | Year | Key features for Nix |
|-----------|------|---------------------|
| z13 | 2015 | **Vector extensions** (SIMD) — hardware CRC32, parallel operations |
| z14 | 2017 | **Vector enhancements** — IEEE 128-bit float, more SIMD |
| z15 | 2019 | **DFLTCC** — hardware deflate compression (zlib/gzip in hardware) |
| z16 | 2022 | **NNPA** — AI accelerator, quantum-safe crypto |
| LinuxONE | — | Same ISA as mainframe Z series |

All currently supported IBM Z hardware is z13 or newer. Setting `-march=z13`
as the minimum enables vector extensions while maintaining full compatibility.

### CPACF — hardware cryptographic acceleration

Every IBM Z processor since z196 (2010) includes CPACF (CP Assist for
Cryptographic Functions), providing near-zero-cost implementations of:

- **AES-128/192/256** — encrypt/decrypt in hardware
- **SHA-1, SHA-256, SHA-512** — hash in hardware
- **GHASH** — GCM authentication in hardware
- **PRNG** — hardware random number generation

Nix uses SHA-256 extensively for store path hashing. With CPACF-enabled OpenSSL,
hash operations run at hardware speed. nixpkgs currently misses this when
cross-compiling because it uses `./Configure linux-generic64` instead of
`./Configure linux64-s390x`.

### DFLTCC — hardware deflate compression

z15+ processors include DFLTCC (Deflate Conversion Call), executing RFC 1951
DEFLATE compression/decompression in a single hardware instruction. This gives:

- **Up to 45x compression speedup** over software zlib
- **Up to 15x decompression speedup**
- Works transparently with standard zlib API when enabled

nixpkgs zlib has **zero DFLTCC configuration** — not even a configure flag.
Enabling it requires `--dfltcc` or `CFLAGS=-DDFLTCC_LEVEL_MASK=0x7e` passed
to zlib's configure. This is a future improvement (requires z15 minimum).

### Vector CRC32

s390x z13+ provides hardware-accelerated CRC32 via vector instructions. zlib
1.3.2 includes s390x-optimized CRC32 code (`contrib/crc32vx/crc32_vx.c`) but
it requires `-mvx -mzvector` compiler flags, which are implied by `-march=z13`.

Without `-march=z13`, the cross-compiler fails to build this code:
```
error: '__builtin_s390_vec_perm' requires '-mvx'
```

IBM maintains a standalone [crc32-s390x](https://github.com/linux-on-ibm-z/crc32-s390x)
library claiming **70x speedup** over slicing-by-8 software implementation.

## nixpkgs Patches for Upstream

We maintain three patches in `nixpkgs-patches/` ready for upstream submission:

| Patch | File | Change |
|-------|------|--------|
| 0001 | `lib/systems/examples.nix` | Add `gcc.arch = "z13"` to s390x — enables vector extensions |
| 0002 | `lib/systems/platforms.nix` | Add `s390x-multiplatform` platform definition |
| 0003 | `openssl/default.nix` | Add `s390x-linux = "./Configure linux64-s390x"` for CPACF |

These benefit the entire NixOS-on-s390x ecosystem, not just our Nix build.

### Future nixpkgs improvements

| Priority | Package | Change | Benefit |
|----------|---------|--------|---------|
| High | zlib | Enable DFLTCC for z15+ targets | 45x compression speedup |
| High | nixpkgs infra | Populate s390x binary cache | Avoid building everything from source |
| Medium | musl | Track upstream IEEE 128-bit long double support | Enables busybox/static builds on s390x |
| Medium | zlib-ng | s390x DFLTCC + CRC32 configuration | Modern zlib replacement with hardware support |
| Low | libsodium | Verify s390x assembly paths enabled | Hardware-accelerated crypto primitives |
| Low | blake3 | s390x SIMD detection | Parallel hashing for Nix store |

## linux-on-ibm-z Organization

IBM's [linux-on-ibm-z](https://github.com/orgs/linux-on-ibm-z/repositories)
GitHub org maintains 350+ repos. Key findings:

- **No patches needed for our deps** — zlib, OpenSSL, sqlite, curl, libgit2,
  boost all work upstream on s390x
- **Patching approach**: fork upstream, create `patch-s390x` branches
- **Notable repos**: `boringssl` (extensive s390x crypto), `crc32-s390x`
  (hardware CRC32 library), `pcre2` (JIT compiler port)
- **Build guides**: `linux-on-ibm-z/docs` repo has a master index of ported
  software with wiki build guides

The org focuses on complex software (databases, orchestration, runtimes) that
needs porting work. Low-level C libraries generally work upstream.

### Implications for nixpkgs

When porting nixpkgs packages to s390x, expect **endianness** to be the dominant
issue category, followed by architecture detection. Packages that do binary
serialization, network protocols, or low-level memory manipulation will almost
certainly need patches. The nix package manager itself has already shown this
pattern (architecture detection in stack.cc and seccomp).

The biggest wins come not from fixing bugs but from **enabling hardware
acceleration** that s390x already has but software doesn't use. The three
nixpkgs patches above are low-effort, high-impact improvements that benefit
every package built for s390x.
