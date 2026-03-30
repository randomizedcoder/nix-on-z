# linux-on-ibm-z Patch Reuse Strategy

[Back to overview](../S390X-PORTING-GUIDE.md)

---

The [linux-on-ibm-z](https://github.com/linux-on-ibm-z) organization maintains **353
repositories** of software ported to s390x. Many contain build scripts and patches that
can be adapted for nixpkgs, saving significant porting effort.

This document prioritizes which linux-on-ibm-z patches to review and adapt for nixpkgs
upstreaming. See [Package Cross-Reference](package-crossref.md) for the full mapping.

## Quick Wins (one-line `meta.platforms` fixes)

These packages work upstream on s390x but are excluded from nixpkgs `meta.platforms`:

| Package | linux-on-ibm-z repo | nixpkgs fix | Unlocks |
|---------|---------------------|-------------|---------|
| **OpenJDK** | `OpenJDK` | Add `"s390x-linux"` to `meta.platforms` | Entire JVM ecosystem: Kafka, Cassandra, Elasticsearch, Spark, Scala, Solr |
| **Grafana** | `grafana` | Add `"s390x-linux"` to `meta.platforms` | Grafana monitoring stack |

These are the highest-ROI changes in the entire porting effort.

## Hardware Acceleration Patches

Patches that enable s390x hardware features (already supported upstream, need nixpkgs wiring):

| Package | linux-on-ibm-z repo | Patch type | Hardware feature | Impact |
|---------|---------------------|------------|-----------------|--------|
| **OpenSSL** | `openssl` | Configure target | CPACF (AES, SHA in hardware) | 73 transitive dependents; near-zero-cost crypto |
| **zlib** | `zlib` | DFLTCC enablement | DFLTCC (hardware deflate) | 95 dependents; 10-50x compression speedup |
| **PCRE2** | `pcre2` + `sljit` | JIT backend | s390x JIT via SLJIT | 108 dependents; regex performance recovery |

OpenSSL CPACF is already applied in our local nixpkgs. zlib DFLTCC and PCRE2 SLJIT are next.

## Hard Problems with High Value

Packages requiring significant patches from linux-on-ibm-z:

| Package | linux-on-ibm-z repo | Patch type | Status | Unlocks |
|---------|---------------------|------------|--------|---------|
| **LuaJIT** | `luajit` | Complete s390x JIT backend | No upstream support; linux-on-ibm-z has only viable port | OpenResty, Kong |
| **BoringSSL** | `boringssl` | s390x crypto assembly | No upstream s390x asm | Envoy, ClickHouse (gRPC), Chromium |
| **Bazel** | `bazel` | Platform detection + s390x config | Complex multi-language build | TensorFlow, all Bazel-built packages |
| **Envoy** | `envoy` | BoringSSL + WASM runtime | Blocked on BoringSSL | Istio service mesh |

## Database Ecosystem

| Package | linux-on-ibm-z repo | Patch type | Notes |
|---------|---------------------|------------|-------|
| **RocksDB** | `rocksdb` | Endianness in block format + CRC SIMD | Unblocks CockroachDB |
| **MongoDB** | `MongoDB` | BSON endianness + WiredTiger asm | Significant work |
| **CockroachDB** | `cockroach` | Go + C++ (inherits RocksDB issues) | Blocked on RocksDB |
| **ClickHouse** | N/A (our case study) | SIMD disable, OpenSSL for gRPC, ICU BE | In progress |

## ML/Data Ecosystem

| Package | linux-on-ibm-z repo | Patch type | Notes |
|---------|---------------------|------------|-------|
| **Apache Arrow** | `arrow` | SIMD in compute kernels | Working but degraded (SIMD disabled) |
| **TensorFlow** | `tensorflow` | SIMD fallbacks + Bazel config | Blocked on Bazel; also broken on x86 |
| **PyTorch** | `pytorch` | ATen kernel intrinsics + MKL-DNN | No MKL-DNN s390x backend |

## Library Ecosystem

| Package | linux-on-ibm-z repo | Patch type | Notes |
|---------|---------------------|------------|-------|
| **libunwind** | `libunwind` | s390x unwinding tables | Unblocks gperftools |
| **gperftools** | `gperftools` | Stack unwinding | Depends on libunwind |
| **OCaml** | `ocaml` | Native code generation | Interpreter works; native needs backend |
| **jemalloc** | `jemalloc` | Page size + TLS tuning | Used by Redis |

## Patch Categories Summary

| Category | Count | Highest priority packages |
|----------|-------|--------------------------|
| Platform detection (`meta.platforms`) | 2 | OpenJDK, Grafana |
| Hardware acceleration | 3 | OpenSSL (CPACF), zlib (DFLTCC), PCRE2 (SLJIT JIT) |
| JIT backends | 4 | LuaJIT, SLJIT/PCRE2, Bazel, OpenResty |
| SIMD replacement | 4 | TensorFlow, PyTorch, Arrow, RocksDB |
| Endianness | 3 | RocksDB, MongoDB, CockroachDB |
| Crypto assembly | 2 | BoringSSL, Envoy |
| Platform-specific runtime | 3 | libunwind, gperftools, OCaml |

## How to Adapt linux-on-ibm-z Patches

1. **Find the repo**: `https://github.com/linux-on-ibm-z/<package>`
2. **Check the build script**: Usually `build_<package>.sh` — contains configure flags, patches, and workarounds
3. **Extract the Nix-relevant parts**:
   - Configure flags -> `cmakeFlags` or `configureFlags`
   - Source patches -> `fetchpatch` from their repo or from upstream PRs they reference
   - Platform guards -> `lib.optionals stdenv.hostPlatform.isS390x`
4. **Prefer upstream fixes**: linux-on-ibm-z often references upstream PRs. If the fix is merged upstream, use `fetchpatch` from the upstream repo
5. **Test progressively**: `--dry-run` -> QEMU -> native hardware

## Recommended Porting Order

1. OpenJDK + Grafana (quick `meta.platforms` wins)
2. zlib DFLTCC (hardware acceleration, high dependents)
3. PCRE2 SLJIT JIT (performance recovery, high dependents)
4. RocksDB (unblocks CockroachDB)
5. libunwind + gperftools (unblocks profiling tools)
6. LuaJIT (hard but unblocks OpenResty/Kong)
7. BoringSSL (hard but unblocks Envoy)
8. Arrow (SIMD optimization, already functional)

---

*Part of the [S390X Nixpkgs Porting Guide](../S390X-PORTING-GUIDE.md). See also:
[Package Cross-Reference](package-crossref.md) | [Priority Plan](priority-plan.md)*
