# Porting Priority Plan

[Back to overview](../S390X-PORTING-GUIDE.md)

---

Packages grouped into priority tiers based on dependency graph analysis.

## Methodology

This section is derived from **actual dependency graph analysis** of the local nix store
database (`/nix/var/nix/db/db.sqlite`), which contains 102,872 store paths and 1,001,713
dependency edges. We queried the 722 s390x-related derivations to compute both direct and
**transitive referrer counts** — i.e., how many other s390x packages would be affected if
a given package fails to build.

The nix build graph for s390x cross-compilation has two distinct subgraphs:
1. **Native build tools** (x86_64) — compilers, build systems, scripts that run on the build host
2. **Target libraries** (s390x) — cross-compiled libraries that s390x packages link against

Both matter: a broken native tool blocks every s390x package that uses it, and a broken
target library blocks everything that depends on it at runtime.

## Build Graph: Root-Level Impact Analysis

### s390x Target Libraries — Ranked by Transitive Impact

These are the cross-compiled s390x libraries. If any of these break, everything below them
in the graph breaks too. Numbers show how many other s390x derivations are transitively
affected.

| Rank | Package | Transitive Dependents | Role |
|------|---------|----------------------:|------|
| 1 | **binutils** (s390x) | 414 | Assembler, linker — everything compiled needs this |
| 2 | **binutils-wrapper** (s390x) | 413 | Nix wrapper around binutils |
| 3 | **nolibc-gcc** (s390x) | 303 | GCC without libc — used to build glibc itself |
| 4 | **glibc-nolibgcc** (s390x) | 299 | glibc built without libgcc — bootstrap chicken-and-egg |
| 5 | **libgcc** (s390x) | 298 | GCC runtime library (exception handling, etc.) |
| 6 | **glibc** (s390x) | 297 | The C library — foundational to everything |
| 7 | **gcc** (s390x) | 290 | The cross-compiler itself |
| 8 | **gcc-wrapper** (s390x) | 289 | Nix wrapper that sets flags/paths |
| 9 | **pkg-config-wrapper** (s390x) | 222 | Library discovery — used by most C/C++ packages |
| 10 | **bash** (s390x) | 121 | Shell — used in build scripts and as `/bin/sh` |
| 11 | **pcre2** (s390x) | 108 | Regular expressions — widely used (JIT disabled on s390x) |
| 12 | **gnugrep** (s390x) | 103 | Pattern matching — used in many build scripts |
| 13 | **zstd** (s390x) | 101 | Compression — used by systemd, LLVM, etc. |
| 14 | **ncurses** (s390x) | 98 | Terminal UI — used by bash, python, etc. |
| 15 | **zlib** (s390x) | 95 | Compression — one of the most depended-on C libs |
| 16 | **tzdata** (s390x) | 90 | Timezone data — used by glibc, python, etc. |
| 17 | **xz** (s390x) | 89 | Compression — used by many tarballs |
| 18 | **attr** (s390x) | 82 | Extended attributes — used by coreutils, systemd |
| 19 | **acl** (s390x) | 81 | Access control lists — used by coreutils, systemd |
| 20 | **tcl** (s390x) | 79 | Tcl interpreter — used by SQLite, expect |
| 21 | **kmod** (s390x) | 76 | Kernel module tools — used by systemd, udev |
| 22 | **openssl** (s390x) | 73 | TLS/crypto — has s390x CPACF hardware acceleration |
| 23 | **bzip2** (s390x) | 69 | Compression |
| 24 | **expat** (s390x) | 69 | XML parsing |
| 25 | **brotli** (s390x) | 68 | Compression — used by curl, nginx |
| 26 | **libxml2** (s390x) | 67 | XML library |
| 27 | **libev** (s390x) | 66 | Event loop — used by curl |
| 28 | **sqlite** (s390x) | 64 | Database — embedded in many applications |
| 29 | **c-ares** (s390x) | 64 | Async DNS — used by curl, Node.js |
| 30 | **nghttp3** (s390x) | 61 | HTTP/3 — used by curl |
| 31 | **lzo** (s390x) | 57 | Compression |
| 32 | **libedit** (s390x) | 55 | Line editing — used by LLVM, python |
| 33 | **keyutils** (s390x) | 55 | Kernel key management |
| 34 | **libunistring** (s390x) | 53 | Unicode strings |
| 35 | **libidn2** (s390x) | 52 | Internationalized domain names |
| 36 | **libseccomp** (s390x) | 43 | Seccomp filters — **critical for s390x** (arch-specific syscalls) |
| 37 | **libsodium** (s390x) | 48 | Modern crypto library |
| 38 | **nlohmann_json** (s390x) | 46 | JSON for C++ |
| 39 | **libssh2** (s390x) | 39 | SSH library — used by curl, git |

### Native Build Tools — Ranked by s390x Build Usage

These are x86_64 packages that run on the build host during s390x cross-compilation.
They don't need to be ported — they just need to keep working.

| Rank | Native Tool | s390x Builds Using It |
|------|-------------|----------------------:|
| 1 | **bash** 5.3 | 394 |
| 2 | **stdenv** (s390x cross) | 266 |
| 3 | **stdenv** (native x86_64) | 97 |
| 4 | **ninja** 1.13.2 | 94 |
| 5 | **meson** 1.10.1 | 86 |
| 6 | **cmake** 4.1.2 | 54 |
| 7 | **gcc-wrapper** 15.2.0 | 44 |
| 8 | **autoreconf-hook** | 43 |
| 9 | **perl** 5.42.0 | 28 |
| 10 | **update-autotools-gnu-config-scripts** | 27 |
| 11 | **python3** 3.13.12 | 23 |
| 12 | **bison** 3.8.2 | 21 |
| 13 | **gettext** 0.26 | 21 |
| 14 | **go** 1.26.1 | 13 |
| 15 | **linux-headers** 6.18.7 | 9 |

## What This Means for Porting

The dependency graph reveals a clear **funnel structure**:

```
binutils (414) → glibc (297) → gcc-wrapper (289) → pkg-config (222) → bash (121)
    ↓                ↓               ↓                   ↓               ↓
Everything       Everything      Everything          Most C/C++      Build scripts
```

**Key insight:** The top 8 packages (binutils through gcc-wrapper) form the **cross-toolchain
bootstrap**. These already work — they're what produces the bootstrap tarballs. If any of these
broke, literally nothing would build.

The **real risk zone** is packages ranked 9-40: `pkg-config`, `bash`, `pcre2`, `zlib`,
`openssl`, `ncurses`, `libseccomp`, etc. These are the first "real" packages built by the
cross-toolchain, and they're where s390x-specific issues (endianness, SIMD, JIT, seccomp)
are most likely to surface. A bug in `zlib` (rank 15, 95 dependents) cascades to break
`curl`, `python3`, `openssl`, `cmake`, and everything downstream.

## Highest-Impact Quick Wins

Based on our research, these nixpkgs changes would unlock the most packages:

| Fix | Change | Unlocks |
|-----|--------|---------|
| **Add s390x to OpenJDK `meta.platforms`** | Add `"s390x-linux"` to platform list | Entire JVM ecosystem: Kafka, Cassandra, Elasticsearch, Scala, Spark, Solr, ActiveMQ, HBase |
| **Add s390x to Grafana `meta.platforms`** | Add `"s390x-linux"` to platform list | Grafana monitoring stack |

Both are likely one-line changes — upstream OpenJDK and Grafana already support s390x.
The nixpkgs expressions simply don't list it.

## Tier 0: Already Working (Verify Only)

These should already work via cross-compilation. Verify with:
```
nix build nixpkgs#pkgsCross.s390x.<package>
```

- **stdenv** — bootstrap tarballs exist (Hydra 268609502)
- Packages in the `release-cross.nix` s390x set
- Pure Go packages (trivial cross-compile with `GOARCH=s390x`)

**Verified** — these 26 packages pass `--dry-run` evaluation (several already cached in binary cache):
`hello`, `coreutils`, `bash`, `zlib`, `openssl`, `curl`, `cmake`, `python3`, `perl`,
`pkg-config`, `go`, `etcd`, `prometheus`, `kubernetes`, `containerd`, `helm`, `nats-server`,
`caddy`, `postgresql`, `redis`, `mariadb`, `nodejs`, `nginx`, `pcre2`, `protobuf`, `sqlite`

## Tier 1: Bootstrap Chain

Core packages that everything else depends on. Bootstrap tarballs prove these *can* work,
but they need to build cleanly from source in nixpkgs stdenv:

| Package | Priority | Notes |
|---------|----------|-------|
| `glibc` | Critical | s390x support upstream; verify nixpkgs expression |
| `gcc` | Critical | s390x backend upstream; check `cc-wrapper` frame pointer |
| `binutils` | Critical | s390x backend upstream |
| `coreutils` | Critical | Highly portable |
| `bash` | Critical | Highly portable |
| `linux-headers` | Critical | s390x headers in upstream kernel |

## Tier 2: Essential Build Dependencies

Required by the vast majority of packages:

| Package | Priority | Notes |
|---------|----------|-------|
| `cmake` | High | Portable; should work |
| `meson` | High | Python-based; should work |
| `pkg-config` | High | Portable C |
| `openssl` | High | s390x CPACF hardware acceleration available |
| `zlib` | High | s390x DFLTCC hardware compression available |
| `curl` | High | Depends on openssl, zlib |
| `python3` | High | CPython has s390x support |
| `perl` | High | Long-standing s390x support |
| `autoconf/automake` | High | Shell/Perl scripts |

## Tier 3: Key Libraries

Widely-depended-on libraries that may need s390x-specific fixes:

| Package | Priority | Notes |
|---------|----------|-------|
| `boost` | Medium | Large; may have SIMD issues in some libs |
| `icu` | Medium | Endianness in data tables |
| `pcre2` | Medium | JIT disabled on s390x (already handled) |
| `sqlite` | Medium | Highly portable |
| `protobuf` | Medium | Wire format is already endian-safe |
| `llvm` | Medium | Has s390x SystemZ backend |
| `libffi` | Medium | Needs s390x calling convention support |

## Tier 4: Applications

High-demand applications, mostly Go-based (should be straightforward):

| Category | Key Packages |
|----------|-------------|
| Containers | `docker`, `containerd`, `podman`, `buildah` |
| Orchestration | `kubernetes`, `helm`, `kustomize` |
| Infrastructure | `terraform`, `vault`, `consul`, `etcd` |
| Databases | `postgresql`, `mariadb`, `redis`, `sqlite` |
| Monitoring | `prometheus`, `grafana`, `alertmanager` |
| Web | `nginx`, `haproxy`, `caddy`, `traefik` |

## Tier 5: Hard Problems

Packages requiring significant porting effort:

| Package | Blocker | Path Forward |
|---------|---------|-------------|
| `luajit` | No s390x JIT backend | linux-on-ibm-z port via SLJIT |
| `envoy` | BoringSSL asm, WASM | linux-on-ibm-z patches |
| `tensorflow` | x86 SIMD kernels | linux-on-ibm-z build scripts |
| `pytorch` | x86 intrinsics in ATen | linux-on-ibm-z patches |
| `bazel` | Complex platform detection | linux-on-ibm-z patches |
| `chromium` | V8 JIT works, but Skia SIMD issues | linux-on-ibm-z patches |
| `firefox` | SpiderMonkey JIT partially works | linux-on-ibm-z patches |
