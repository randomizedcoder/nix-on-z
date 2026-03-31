# Current State of s390x in Nixpkgs

[Back to overview](../S390X-PORTING-GUIDE.md)

---

## What Already Exists

Nixpkgs has foundational s390x support. The following infrastructure is already in place:

| What | Where in nixpkgs | Status |
|------|-------------------|--------|
| CPU type definitions | `lib/systems/parse.nix:319-328` | `s390` (32-bit BE) and `s390x` (64-bit BE) defined |
| Platform predicates | `lib/systems/inspect.nix:232-242` | `isS390` and `isS390x` predicates available |
| System doubles | `lib/systems/doubles.nix` | `s390-linux` and `s390x-linux` included in `all` |
| Cross-compilation example | `lib/systems/examples.nix` | `s390x = { config = "s390x-unknown-linux-gnu"; }` |
| Bootstrap tarballs | `pkgs/stdenv/linux/bootstrap-files/s390x-unknown-linux-gnu.nix` | Hydra build 268609502 (Aug 2024) |
| Cross-compilation CI | `pkgs/top-level/release-cross.nix` | `s390x = mapTestOnCross ...` with package set |
| Dynamic linker path | `pkgs/build-support/bintools-wrapper/default.nix` | `ld64.so.1` for s390x |
| Frame pointer handling | `pkgs/build-support/cc-wrapper/default.nix:854-857` | s390x skips `-fno-omit-frame-pointer` (glibc build failures + perf regressions) |
| PCRE2 JIT disable | `pkgs/development/libraries/pcre2/default.nix:26` | `--enable-jit=no` when `isS390x` |
| OpenBLAS target | `pkgs/development/libraries/science/math/openblas/make.nix:140` | `TARGET = "ZARCH_GENERIC"` with dynamic arch support |
| Rust bootstrap | `pkgs/development/compilers/rust/1_94.nix:86` | s390x-unknown-linux-gnu hash present |
| Go bootstrap | `pkgs/development/compilers/go/bootstrap124.nix:25` | linux-s390x hash present |
| musl | `pkgs/by-name/mu/musl/package.nix:208` | s390x-linux in platforms |
| Valgrind | `pkgs/by-name/va/valgrind/package.nix:117` | s390x in supported platforms |
| IBM Cloud CLI | `pkgs/by-name/ib/ibmcloud-cli/package.nix:20` | Pre-built s390x binary |

## Known Gaps

These are the missing pieces that need to be addressed for full native s390x support:

| Gap | File | Impact |
|-----|------|--------|
| **Not in flake-systems** | `lib/systems/flake-systems.nix` | Cannot use `nixpkgs.legacyPackages.s390x-linux` in flakes natively |
| **No `architectures.nix` entries** | `lib/systems/architectures.nix` | No `-march` flag variants (unlike x86-64-v2/v3/v4). s390x has z13/z14/z15/z16 but these aren't mapped |
| **~~No `platforms.nix` kernel config~~** | `lib/systems/platforms.nix` | **Fixed**: `s390x-multiplatform` definition added with bzImage target, autoModules, defconfig |
| **No musl bootstrap** | `pkgs/stdenv/linux/bootstrap-files/` | Only `s390x-unknown-linux-gnu.nix` exists — no `s390x-unknown-linux-musl.nix` |
| **No native Hydra builder** | Hydra infrastructure | All s390x builds are cross-compiled from x86_64 — no native CI |

## Bootstrap Tarballs Detail

The s390x bootstrap tarballs were built via Hydra build **268609502** (August 2024) and contain:

- `bootstrap-tools.tar.xz` — gcc, glibc, binutils, coreutils, etc.
- `busybox` — static busybox for early bootstrap
- Individual tarballs for bootstrap stdenv components

These are fetched from `https://hydra.nixos.org/build/268609502/download/1/` in
`pkgs/stdenv/linux/bootstrap-files/s390x-unknown-linux-gnu.nix`.

## nix-on-z Patches Applied (local nixpkgs clone)

The following patches have been applied to our nixpkgs working copy on branch
`s390x-clickhouse` and are candidates for upstream contribution:

| Patch | File | Effect |
|-------|------|--------|
| `gcc.arch=z13` | `lib/systems/examples.nix` | Enables vector extension (VXE) instructions for s390x cross-builds |
| `s390x-multiplatform` | `lib/systems/platforms.nix` | Adds platform definition + `select` clause (closes the gap above) |
| OpenSSL `linux64-s390x` | `pkgs/development/libraries/openssl/default.nix` | Enables CPACF hardware crypto acceleration |
| ClickHouse s390x | `pkgs/by-name/cl/clickhouse/generic.nix` | Relaxes broken flag, disables x86 SIMD, forces OpenSSL for gRPC, fixes ICU BE |

### Dependency chain verification (dry-run)

All critical ClickHouse dependencies evaluate for s390x cross-compilation:

```
hello zlib openssl cmake python3 perl rustc cargo llvm  — all pass --dry-run
clickhouse                                               — passes --dry-run
```
