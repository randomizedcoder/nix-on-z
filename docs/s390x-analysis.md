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

### Implications for nixpkgs

When porting nixpkgs packages to s390x, expect **endianness** to be the dominant
issue category, followed by architecture detection. Packages that do binary
serialization, network protocols, or low-level memory manipulation will almost
certainly need patches. The nix package manager itself has already shown this
pattern (architecture detection in stack.cc and seccomp).
