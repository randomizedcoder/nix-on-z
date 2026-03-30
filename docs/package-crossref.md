# Cross-Reference: linux-on-ibm-z to Nixpkgs

[Back to overview](../S390X-PORTING-GUIDE.md)

---

The [linux-on-ibm-z](https://github.com/linux-on-ibm-z) GitHub organization maintains
**353 repositories** of software ported to s390x. This section maps those repos to their
nixpkgs equivalents.

**Legend:**
- **Status**: `upstream` = s390x support merged upstream; `patched` = needs linux-on-ibm-z patches; `wip` = work in progress; `unknown` = needs investigation
- **Difficulty**: `trivial` = just enable s390x; `easy` = minor patches; `medium` = significant patching; `hard` = JIT/asm rewrite needed

## Compilers & Language Runtimes

| linux-on-ibm-z repo | nixpkgs package | Status | Difficulty | Notes |
|----------------------|-----------------|--------|------------|-------|
| `go` | `pkgs.go` | upstream | trivial | Go has native s390x support since 1.7 |
| `swift` | `pkgs.swift` | patched | hard | Swift runtime needs s390x patches |
| `llvm-project` | `pkgs.llvm` | upstream | trivial | LLVM has s390x SystemZ backend |
| `ruby` | `pkgs.ruby` | upstream | easy | Minor test fixes needed |
| `scala` | `pkgs.scala` | upstream | trivial | JVM-based, works if OpenJDK works |
| `ocaml` | `pkgs.ocaml` | patched | medium | Native code gen needs s390x support |
| `python-build-standalone` | `pkgs.python3` | upstream | easy | CPython has s390x support |
| `gcc` | `pkgs.gcc` | upstream | trivial | GCC has full s390x backend |
| `OpenJDK` | `pkgs.openjdk` | upstream | easy | IBM contributes s390x JIT (C2); **s390x excluded from `meta.platforms` in nixpkgs** — highest-priority fix |
| `node` | `pkgs.nodejs` | upstream | easy | V8 has IBM-maintained s390x backend |

**Cross-compilation verification** (`nix build nixpkgs#pkgsCross.s390x.<pkg> --dry-run`):
- `go`: **PASS** — Go 1.26.1; native s390x cross-compilation support
- `python3`: **PASS** — Python 3.13.12; large build graph with libffi, gdbm, mpdecimal
- `nodejs`: **PASS** — Node.js 24.14.0; builds ICU, simdutf, simdjson cross-compiled
- `openjdk`: **FAIL** — `meta.platforms` lists x86_64, aarch64, armv7l, armv6l, ppc64le, riscv64 but **no s390x**. This is a nixpkgs packaging gap — upstream OpenJDK has full s390x support via IBM's C2 JIT.

**Existing s390x handling in nixpkgs:**
- Rust (`pkgs/development/compilers/rust/1_94.nix:86`): bootstrap hash for `s390x-unknown-linux-gnu`
- Go (`pkgs/development/compilers/go/bootstrap124.nix:25`): bootstrap hash for `linux-s390x`
- Flutter engine (`pkgs/development/compilers/flutter/engine/constants.nix:29`): maps `isS390x` -> `"s390x"`

## Databases

| linux-on-ibm-z repo | nixpkgs package | Status | Difficulty | Notes |
|----------------------|-----------------|--------|------------|-------|
| `mariadb` | `pkgs.mariadb` | upstream | easy | Minor endianness fixes in storage engines |
| `mysql` | `pkgs.mysql` | upstream | easy | Similar to mariadb |
| `cassandra` | `pkgs.cassandra` | upstream | trivial | JVM-based |
| `couchdb` | `pkgs.couchdb` | upstream | easy | Erlang-based, needs Erlang s390x |
| `hbase` | -- | upstream | trivial | JVM-based; not in nixpkgs |
| `cockroach` | `pkgs.cockroachdb` | patched | medium | Go + C++ with RocksDB |
| `rocksdb` | `pkgs.rocksdb` | patched | medium | Endianness in block format, SIMD in CRC |
| `elasticsearch` | `pkgs.elasticsearch` | upstream | trivial | JVM-based |
| `postgres` | `pkgs.postgresql` | upstream | easy | Long-standing s390x support |
| `etcd` | `pkgs.etcd` | upstream | trivial | Pure Go |
| `consul` | `pkgs.consul` | upstream | trivial | Pure Go |
| `redis` | `pkgs.redis` | upstream | easy | Minor asm in `zmalloc`, JIT in jemalloc |
| `sqlite` | `pkgs.sqlite` | upstream | trivial | Highly portable C |
| `MongoDB` | `pkgs.mongodb` | patched | hard | Endianness in BSON, x86 asm in WiredTiger |

**Cross-compilation verification:**
- `postgresql`: **PASS** — pulls in ICU, LLVM 21.1.8, readline, perl
- `mariadb`: **PASS** — 98 derivations; heaviest build (670 MiB fetch, ~2.7 GiB unpacked); boost, judy, zeromq
- `redis`: **PASS** — 90 derivations; pulls in full LLVM/clang, systemd, gnupg, cryptsetup
- `sqlite`: **PASS** — 2 derivations (zlib + sqlite 3.51.2)
- `etcd`: **PASS** — 9 derivations; builds etcdserver, etcdctl, etcdutl (3.6.8)

## Container & Cloud Infrastructure

| linux-on-ibm-z repo | nixpkgs package | Status | Difficulty | Notes |
|----------------------|-----------------|--------|------------|-------|
| `moby` | `pkgs.docker` | upstream | easy | Go-based; docker daemon works on s390x |
| `containerd` | `pkgs.containerd` | upstream | trivial | Pure Go |
| `runc` | `pkgs.runc` | upstream | trivial | Go + minor cgo; s390x seccomp |
| `kubernetes` | `pkgs.kubernetes` | upstream | easy | Go; some test fixtures need updating |
| `terraform` | `pkgs.terraform` | upstream | trivial | Pure Go |
| `vault` | `pkgs.vault` | upstream | trivial | Pure Go |
| `helm` | `pkgs.helm` | upstream | trivial | Pure Go |
| `calico` | -- | upstream | easy | Not directly in nixpkgs as package |
| `flannel` | `pkgs.flannel` | upstream | trivial | Pure Go |
| `kind` | `pkgs.kind` | upstream | trivial | Pure Go |
| `minikube` | `pkgs.minikube` | upstream | easy | Go; needs s390x VM/container images |
| `podman` | `pkgs.podman` | upstream | easy | Go + minor cgo |
| `buildah` | `pkgs.buildah` | upstream | trivial | Pure Go |
| `skopeo` | `pkgs.skopeo` | upstream | trivial | Pure Go |
| `cri-o` | `pkgs.cri-o` | upstream | trivial | Pure Go |
| `istio` | -- | patched | medium | Go + Envoy proxy (C++ with BoringSSL) |
| `envoy` | `pkgs.envoy` | patched | hard | C++ with BoringSSL asm, WASM |
| `cni-plugins` | `pkgs.cni-plugins` | upstream | trivial | Pure Go |
| `kustomize` | `pkgs.kustomize` | upstream | trivial | Pure Go |
| `argo-cd` | `pkgs.argocd` | upstream | trivial | Pure Go |
| `packer` | `pkgs.packer` | upstream | trivial | Pure Go |

**Cross-compilation verification** — All Go packages evaluated successfully:
- `kubernetes`: **PASS** — 4 derivations; kubectl + kubernetes 1.35.2
- `containerd`: **PASS** — 20 derivations; pulls in btrfs-progs, e2fsprogs, systemd (CGO deps)
- `helm`: **PASS** — 68 derivations; large dependency tree including systemd
- `etcd`: **PASS** — 9 derivations; clean build
- `nats-server`: **PASS** — 3 derivations; clean Go build
- `caddy`: **PASS** — 3 derivations; uses Go 1.25.8 (pinned older Go)
- `prometheus`: **PASS** — 31 derivations; requires building Node.js for web UI asset pipeline
- `terraform`: **FAIL (license)** — BSL unfree license, not an s390x issue
- `consul`: **FAIL (license)** — BSL unfree license, not an s390x issue

Go's native cross-compilation (`GOOS=linux GOARCH=s390x`) makes all pure-Go packages trivial.
CGO packages (containerd, helm) also evaluate fine — the C dependencies resolve for s390x.

## Data & ML

| linux-on-ibm-z repo | nixpkgs package | Status | Difficulty | Notes |
|----------------------|-----------------|--------|------------|-------|
| `tensorflow` | `pkgs.python3Packages.tensorflow` | patched | hard | x86 SIMD in kernels, Bazel build |
| `numpy` | `pkgs.python3Packages.numpy` | upstream | easy | Uses openblas which has ZARCH target |
| `spark` | `pkgs.spark` | upstream | trivial | JVM-based |
| `solr` | -- | upstream | trivial | JVM-based; not in nixpkgs |
| `arrow` | `pkgs.arrow-cpp` | patched | medium | SIMD in compute kernels |
| `pytorch` | `pkgs.python3Packages.pytorch` | patched | hard | x86 intrinsics in ATen |
| `scipy` | `pkgs.python3Packages.scipy` | upstream | easy | Fortran + C; works with s390x openblas |
| `pandas` | `pkgs.python3Packages.pandas` | upstream | trivial | Pure Python + Cython |

**Deep-dive: TensorFlow s390x blockers** (`pkgs/development/python-modules/tensorflow/default.nix`):
1. **Platform hashes missing** (lines 519-532): Only x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin have sha256 checksums
2. **x86 SIMD hard-coded** (lines 79-81, 465-467): `sse42Support`, `avx2Support`, `fmaSupport` flags with no s390x VXE equivalent
3. **Bazel build**: No s390x build configuration exists
4. **Currently broken**: Line 598 marks the package as broken due to EOL dependencies — even x86 is affected

**Deep-dive: PyTorch s390x blockers** (`pkgs/development/python-modules/torch/source/default.nix`):
1. **Platform matrix narrow** (line 776): Only x86_64-linux, aarch64-linux, aarch64-darwin explicitly supported
2. **No CPU intrinsic fallbacks**: Uses x86/ARM SIMD with no generic fallback for s390x
3. **MKL-DNN** (line 82): `mklDnnSupport` disabled on non-x86; oneDNN has no s390x backend
4. **CUDA-only GPU** (lines 245-252): Not applicable to s390x, but no CPU-optimized alternative path

**Deep-dive: Arrow-cpp** (`pkgs/by-name/ar/arrow-cpp/package.nix`):
- Lines 279-280: Explicitly disables SIMD for non-x86_64: `(lib.cmakeBool "ARROW_USE_SIMD" false)` — functional but slow on s390x

**NumPy/SciPy** already have big-endian test exclusion patterns from Power64 (ppc64) that can be reused for s390x:
- NumPy (`pkgs/development/python-modules/numpy/2.nix:142-144`): Known test failures on Power64 BE
- SciPy (`pkgs/development/python-modules/scipy/default.nix:133-140`): 6 tests excluded on Power64 BE

## Messaging & Streaming

| linux-on-ibm-z repo | nixpkgs package | Status | Difficulty | Notes |
|----------------------|-----------------|--------|------------|-------|
| `kafka` | `pkgs.apacheKafka` | upstream | trivial | JVM-based |
| `rabbitmq` | `pkgs.rabbitmq-server` | upstream | trivial | Erlang-based |
| `activemq` | -- | upstream | trivial | JVM-based; not in nixpkgs |
| `nats-server` | `pkgs.nats-server` | upstream | trivial | Pure Go |
| `pulsar` | -- | upstream | trivial | JVM-based; not in nixpkgs |
| `mosquitto` | `pkgs.mosquitto` | upstream | trivial | Portable C |
| `ZeroMQ` | `pkgs.zeromq` | upstream | easy | C++ with minor platform tweaks |

Note: JVM-based packages (Kafka, ActiveMQ, Pulsar) depend on OpenJDK, which currently
excludes s390x from `meta.platforms` in nixpkgs — fixing OpenJDK is a prerequisite.
Erlang-based packages (RabbitMQ) depend on Erlang/OTP which has upstream s390x support
but has not been verified in nixpkgs cross-compilation.

## Monitoring & Observability

| linux-on-ibm-z repo | nixpkgs package | Status | Difficulty | Notes |
|----------------------|-----------------|--------|------------|-------|
| `prometheus` | `pkgs.prometheus` | upstream | trivial | Pure Go |
| `grafana` | `pkgs.grafana` | upstream | easy | Go backend + Node.js frontend; **s390x excluded from `meta.platforms`** — needs fix |
| `jaeger` | `pkgs.jaeger` | upstream | trivial | Pure Go |
| `zabbix` | `pkgs.zabbix` | upstream | easy | C with minor portability fixes |
| `fluentd` | `pkgs.fluentd` | upstream | trivial | Ruby-based |
| `Thanos` | `pkgs.thanos` | upstream | trivial | Pure Go |
| `alertmanager` | `pkgs.alertmanager` | upstream | trivial | Pure Go |
| `node_exporter` | `pkgs.prometheus-node-exporter` | upstream | trivial | Pure Go |
| `Loki` | `pkgs.grafana-loki` | upstream | trivial | Pure Go |

## Web & Proxy

| linux-on-ibm-z repo | nixpkgs package | Status | Difficulty | Notes |
|----------------------|-----------------|--------|------------|-------|
| `envoy` | `pkgs.envoy` | patched | hard | BoringSSL asm, WASM runtime |
| `kong` | -- | patched | medium | Depends on OpenResty/LuaJIT |
| `openresty` | `pkgs.openresty` | patched | hard | LuaJIT has no s390x backend |
| `nginx` | `pkgs.nginx` | upstream | trivial | Pure C, highly portable |
| `HAProxy` | `pkgs.haproxy` | upstream | easy | C with optional s390x-specific atomics |
| `traefik` | `pkgs.traefik` | upstream | trivial | Pure Go |
| `caddy` | `pkgs.caddy` | upstream | trivial | Pure Go |

## Build Tools

| linux-on-ibm-z repo | nixpkgs package | Status | Difficulty | Notes |
|----------------------|-----------------|--------|------------|-------|
| `bazel` | `pkgs.bazel` | patched | hard | Java + C++ + platform detection |
| `protobuf` | `pkgs.protobuf` | upstream | easy | C++ with minor endianness in wire format |
| `flatbuffers` | `pkgs.flatbuffers` | upstream | easy | Endianness handling already present |
| `buf` | `pkgs.buf` | upstream | trivial | Pure Go |
| `rules_rust` | -- | patched | medium | Bazel rule set; not a nixpkgs package |
| `rules_python` | -- | patched | medium | Bazel rule set; not a nixpkgs package |
| `cmake` | `pkgs.cmake` | upstream | trivial | Highly portable C++ |
| `ninja` | `pkgs.ninja` | upstream | trivial | Portable C++ |
| `meson` | `pkgs.meson` | upstream | trivial | Python-based |

## Low-Level & Runtime Libraries

This category has the most interesting porting challenges and the highest impact for
unblocking other packages.

| linux-on-ibm-z repo | nixpkgs package | Status | Difficulty | Notes |
|----------------------|-----------------|--------|------------|-------|
| `sljit` | -- | patched | hard | JIT compiler backend; s390x port exists |
| `pcre2` | `pkgs.pcre2` | upstream | easy | JIT disabled on s390x; scalar fallback works |
| `gperftools` | `pkgs.gperftools` | patched | medium | Stack unwinding, `libunwind` dependency |
| `libunwind` | `pkgs.libunwind` | patched | medium | s390x unwinding tables |
| `boringssl` | `pkgs.boringssl` | patched | hard | x86 asm in crypto primitives |
| `dpdk` | `pkgs.dpdk` | patched | hard | Deep hardware-specific code |
| `abseil-cpp` | `pkgs.abseil-cpp` | upstream | easy | Minor endianness fixes |
| `luajit` | `pkgs.luajit` | patched | hard | No upstream s390x; linux-on-ibm-z port |
| `seastar` | -- | patched | hard | Coroutine/fiber runtime, asm stack switching |
| `openssl` | `pkgs.openssl` | upstream | easy | s390x crypto acceleration patches (CPACF) |
| `zlib` | `pkgs.zlib` | upstream | easy | s390x DFLTCC hardware compression |
| `zstd` | `pkgs.zstd` | upstream | easy | Portable C with optional asm |
| `lz4` | `pkgs.lz4` | upstream | trivial | Portable C |
| `snappy` | `pkgs.snappy` | upstream | easy | Minor SIMD detection |
| `jemalloc` | `pkgs.jemalloc` | upstream | easy | s390x page size and TLS handling |

## Specialized s390x

These are s390x-specific projects with no x86 equivalent:

| linux-on-ibm-z repo | Description | Relevance |
|----------------------|-------------|-----------|
| `crc32-s390x` | Hardware CRC32 using s390x vector instructions | Could accelerate RocksDB, Ceph, etc. |
| `sljit` (s390x backend) | JIT compiler backend for s390x | Unblocks PCRE2 JIT, OpenResty/LuaJIT |
| `linux-on-ibm-z.github.io` | Porting documentation website | Reference material |
