# nix-on-z

Bootstrapping [Nix](https://github.com/NixOS/nix) on IBM Z (s390x) from source.

This repo contains everything needed to build and install Nix on an IBM
LinuxONE / z machine running Ubuntu 22.04. The upstream Nix codebase does not
yet ship s390x support, and Ubuntu 22.04's packages are too old for several
dependencies. We solve both problems: small code patches add s390x arch
support, and a set of numbered shell scripts build the missing dependencies
from source, then configure, build, and install Nix itself.

## Test Results (s390x, 2026-03-28)

| | Pass | Fail | Skip | Notes |
|---|---:|---:|---:|---|
| **Unit tests** | 1,846 | 0 | 0 | 5 suites, all pass |
| **Functional tests** | 109 | 2 | 16 | 85.8% pass, 98.4% pass+skip |

The 2 functional test failures are upstream `TODO_NixOS` issues that fail
identically on x86_64 Ubuntu:

- **structured-attrs.sh** -- `nix develop` needs `flake:nixpkgs` in the test's
  isolated flake registry, which is only populated on NixOS.
- **nested-sandboxing.sh** -- requires Nix's own dependencies in `/nix/store`,
  which only exists when Nix itself was installed from nixpkgs.

**No failures are s390x-specific.**

## Nix Source Patches

Five patches are required. Two add s390x architecture support. Three fix test
infrastructure bugs that affect all platforms (not s390x-specific). Patches
are applied to a clean checkout of [NixOS/nix](https://github.com/NixOS/nix)
master.

| Patch | File(s) | Category | Summary |
|-------|---------|----------|---------|
| 0001 | `stack.cc`, `linux-derivation-builder.cc` | s390x | Architecture detection: stack pointer + seccomp |
| 0002 | `vars.sh` | all platforms | Fix unbound `$NIX_STORE` variable |
| 0003 | `subst-vars.sh.in`, `vars.sh` | all platforms | Add missing `$shell` test variable |
| 0004 | `fetchGitSubmodules.sh` | all platforms | Fix recursive git submodule transport |
| 0005 | `derivation-builder.cc` | all platforms | Fix sandbox ownership check for non-root builds |

### Patch 1: s390x architecture support

**Stack pointer detection** (`src/libmain/unix/stack.cc`) -- adds s390x stack
pointer register (R15 = `gregs[15]`) for the SIGSEGV stack overflow detector:

```cpp
#elif defined(__s390x__)
    sp = (char *) ((ucontext_t *) ctx)->uc_mcontext.gregs[15];
```

**Seccomp architecture** (`src/libstore/unix/build/linux-derivation-builder.cc`)
-- adds the 31-bit s390 compat architecture for the seccomp sandbox filter,
following the existing pattern for aarch64/ARM and x86_64/x86:

```cpp
if (nativeSystem == "s390x-linux" && seccomp_arch_add(ctx, SCMP_ARCH_S390) != 0)
    printError("unable to add s390 seccomp architecture");
```

### Patch 2: Fix unbound NIX_STORE variable

On non-NixOS systems, `NIX_STORE` is not set. With bash's `set -u` (nounset),
the bare `$NIX_STORE` reference in `tests/functional/common/vars.sh` causes an
"unbound variable" error, making all functional tests fail.

Fix: `$NIX_STORE` -> `${NIX_STORE-}` (default to empty when unset).

### Patch 3: Add `$shell` test variable

Several functional tests (`formatter.sh`, `nix-profile.sh`) use `${shell}` in
heredocs to create derivation build scripts. This variable was never defined in
the test infrastructure for non-NixOS systems, causing "unbound variable"
failures.

Fix: add `shell=@bash@` to `tests/functional/common/subst-vars.sh.in` and
export it from `vars.sh`.

### Patch 4: Fix recursive git submodule transport

`fetchGitSubmodules.sh` fails on the nested submodule test because
`GIT_CONFIG_COUNT` environment variables do not propagate through recursive
`git submodule update` helper processes on older git versions (e.g., 2.34.1).

Fix: use `git -c protocol.file.allow=always` instead of relying on
`GIT_CONFIG_COUNT` environment variables. The `-c` flag sets
`GIT_CONFIG_PARAMETERS` which does propagate to recursive subprocesses.

### Patch 5: Fix sandbox ownership check for non-root builds

The sandbox output validation in `src/libstore/unix/build/derivation-builder.cc`
unconditionally rejects build outputs with group-writable or world-writable
permission bits. This check is designed for builds running as root with
dedicated build users, where group/world-writable files indicate potential
tampering.

However, when running as a non-root user (the common case for unit tests and
development builds), there are no build users -- the builder runs as the calling
user with the caller's umask. A standard Ubuntu umask of `0002` creates files
with group-writable bits (`0664`), which triggers the rejection even though no
security concern exists. The permission bits are canonicalised immediately after
the check anyway.

Fix: gate the group/world-writable permission check on `buildUser` being
non-null, matching the existing UID ownership check which is already gated.
This fixes 9 C API test failures (`nix_api_store_test`, `nix_api_expr_test`)
that build derivations inside the test harness.

## How to Reproduce

### Prerequisites

1. An s390x machine running Ubuntu 22.04 (e.g., IBM LinuxONE Community Cloud)
2. A local workstation with SSH access to the s390x machine
3. A fork or clone of [NixOS/nix](https://github.com/NixOS/nix)

### Step 1: Clone the repos

On your workstation, set up three repos side-by-side:

```bash
cd ~/Downloads

# This repo -- bootstrap scripts + patches
git clone https://github.com/randomizedcoder/nix-on-z.git

# NixOS/nix source
git clone https://github.com/randomizedcoder/nix.git
cd nix
git checkout origin/master  # clean upstream master

# RapidCheck fork with -fPIC fix for s390x
cd ~/Downloads
git clone -b nix-on-z https://github.com/randomizedcoder/rapidcheck.git
```

### Step 2: Apply patches

```bash
cd ~/Downloads/nix
git apply ../nix-on-z/patches/0001-add-s390x-support.patch
git apply ../nix-on-z/patches/0002-fix-functional-tests-unbound-NIX_STORE.patch
git apply ../nix-on-z/patches/0003-add-shell-test-variable.patch
git apply ../nix-on-z/patches/0004-fix-fetchGitSubmodules-recursive-transport.patch
git apply ../nix-on-z/patches/0005-fix-sandbox-ownership-check-non-root.patch
```

Verify patches applied correctly:

```bash
grep '__s390x__' src/libmain/unix/stack.cc                        # Patch 1
grep 'NIX_STORE-' tests/functional/common/vars.sh                 # Patch 2
grep '^shell=' tests/functional/common/subst-vars.sh.in           # Patch 3
grep 'protocol.file.allow=always' tests/functional/fetchGitSubmodules.sh  # Patch 4
grep 'buildUser' src/libstore/unix/build/derivation-builder.cc | grep -c 'if (buildUser'  # Patch 5 (should show 1)
```

### Step 3: Configure SSH

Add an entry to `~/.ssh/config` so `ssh z` reaches the target machine:

```
Host z
  Hostname <your-s390x-ip>
  User <your-username>
```

### Step 4: Sync to the s390x machine

```bash
cd ~/Downloads/nix-on-z
bash sync-to-z.sh
```

This rsyncs three things to the remote:

| Local path | Remote path | What |
|---|---|---|
| `~/Downloads/nix/` | `z:nix/` | Patched Nix source |
| `~/Downloads/rapidcheck/` | `z:rapidcheck/` | RapidCheck fork with `-fPIC` fix |
| `nix-on-z/*.sh` + `patches/` | `z:nix-on-z/` | Bootstrap scripts and patches |

### Step 5: Build everything on the s390x machine

```bash
ssh z

# Phase 1: Install system packages and build toolchain
cd ~/nix-on-z
sudo bash 00-apt-deps.sh
bash 01-meson-pip.sh
bash 02-gcc14.sh              # ~2-4 hours at -j1
source 03-env.sh

# Phase 2: Build dependencies from source
bash 04-boost.sh              # ~20-30 min at -j1
bash 05-nlohmann-json.sh
bash 06-toml11.sh
bash 07-sqlite.sh
bash 08-boehm-gc.sh
bash 09-curl.sh
bash 10-libgit2.sh
bash 11-libseccomp.sh
bash 12-blake3.sh

# Phase 3: Build and install Nix
source 03-env.sh
cd ~/nix && bash ~/nix-on-z/13-nix-build.sh
bash ~/nix-on-z/14-nix-install.sh
nix --version                  # should print: nix (Nix) 2.35.0
```

Total time: ~3-5 hours (GCC 14 dominates).

### Step 6: Run tests

```bash
# Install test dependencies
cd ~/nix-on-z
bash 15-test-deps.sh           # GoogleTest, RapidCheck

# Rebuild with tests enabled
bash 16-nix-build-tests.sh

# Verify the test environment
bash 18-verify-test-env.sh     # should exit 0 with all PASS

# Run all tests
source 03-env.sh
cd ~/nix
bash ~/nix-on-z/17-run-tests.sh
```

Expected results: 1,846 unit tests pass, 109/2/16 functional pass/fail/skip.

### Step 7: Verify

```bash
nix --version
# nix (Nix) 2.35.0

nix --extra-experimental-features nix-command store info
# Store URL: local
# Version: 2.35.0
# Trusted: 1

nix --extra-experimental-features nix-command eval --expr '1 + 1'
# 2
```

## Target Environment

| | |
|---|---|
| **Architecture** | s390x (IBM z16 / LinuxONE) |
| **OS** | Ubuntu 22.04 LTS |
| **RAM** | 3.9 GiB (scripts use `-j1` where needed to avoid OOM) |
| **Disk** | ~45 GB free recommended |
| **Nix version** | 2.35.0 (built from source) |

## Why So Many Dependencies From Source?

Ubuntu 22.04 is a stable LTS release, but Nix 2.35 requires C++23 and recent
versions of several libraries. Building GCC 14 from source gives us C++23
support, but it also creates a "split-world" problem: system libraries were
compiled with GCC 12, while Nix is compiled with GCC 14. This exposed
compatibility issues in 4 additional system packages that we also had to build
from source.

## Dependency Details

| Dependency | Required | Ubuntu 22.04 | Problem | Built Version |
|-----------|----------|-------------|---------|---------------|
| GCC | C++23 | 12 | No C++23 support | 14.2.0 |
| Boost | >= 1.87 | 1.74 | Too old | 1.87.0 |
| nlohmann_json | >= 3.9 | 3.10.5 | `std::pair` conversion fails with GCC 14 | 3.11.3 |
| toml11 | >= 3.7 | 3.7.0 (apt) | No cmake config files for meson detection | 4.4.0 |
| SQLite | >= 3.38 | 3.37.2 | Missing `sqlite3_error_offset()` | 3.49.1 |
| Boehm GC | >= 8.2 | 8.0.6 | `traceable_allocator<void>::value_type` is private | 8.2.8 |
| libcurl | >= 8.17 | 7.81.0 | Too old | 8.17.0 |
| libgit2 | >= 1.9 | 1.1.0 | Too old | 1.9.0 |
| libseccomp | >= 2.5.5 | 2.5.3 | Too old | 2.5.5 |
| BLAKE3 | any | N/A | Not packaged | 1.8.2 |

## Meson Build Flags

```
-Dlibstore:sandbox-shell=/usr/bin/bash-static  # static shell for sandbox chroot
-Dlibcmd:readline-flavor=readline              # editline not available on Ubuntu 22.04
-Ddoc-gen=false                                # skip documentation generation
-Dunit-tests=true                              # enable test compilation
-Dbindings=false                               # skip Perl bindings
-Dbenchmarks=false                             # skip benchmarks
-Djson-schema-checks=false                     # skip JSON schema validation
```

## Sandbox Shell: bash-static, not busybox

Nix builds derivations inside a sandboxed chroot where almost nothing from the
host filesystem exists. Derivations need a shell (`/bin/sh`) to run build
commands. This shell must be **statically linked** since no shared libraries are
available inside the empty chroot.

By default, meson searches for `busybox` as the sandbox shell. On Ubuntu 22.04,
`busybox-static` is available but causes problems:

- The 19 functional tests that check for `$busybox` will **run instead of
  skip**, then fail because Ubuntu's busybox doesn't handle the test scenarios
- Unit tests that build derivations work fine with busybox

The solution: use **`bash-static`** instead:

```bash
sudo apt-get install -y bash-static
sudo apt-get remove -y busybox-static  # prevent meson from detecting it

# Configure with bash-static as the sandbox shell
meson setup build --reconfigure \
    -Dlibstore:sandbox-shell=/usr/bin/bash-static
```

This gives full sandboxed build support while keeping the busybox-dependent
functional tests in their expected skip state.

## Scripts

Each script is self-contained, idempotent (safe to re-run), and prints a
completion message on success. They install everything into `/usr/local`.

| Script | Phase | What it does | Time |
|--------|-------|-------------|------|
| `00-apt-deps.sh` | 0 | Installs Ubuntu packages, removes busybox-static, installs bash-static | ~2 min |
| `01-meson-pip.sh` | 1 | Installs meson >= 1.1 via pip (Ubuntu ships 0.61) | ~1 min |
| `02-gcc14.sh` | 2 | Builds GCC 14.2.0 from source for C++23 support | ~2-4 hrs |
| `03-env.sh` | 3 | Sets CC, CXX, PATH, LD_LIBRARY_PATH, PKG_CONFIG_PATH (source, don't execute) | -- |
| `04-boost.sh` | 4 | Builds Boost 1.87.0 (Ubuntu has 1.74, too old) | ~20-30 min |
| `05-nlohmann-json.sh` | 5 | Installs nlohmann_json 3.11.3 (Ubuntu's 3.10.5 fails with GCC 14) | ~1 min |
| `06-toml11.sh` | 6 | Installs toml11 4.4.0 (Ubuntu's apt pkg lacks cmake config files) | ~1 min |
| `07-sqlite.sh` | 7 | Builds SQLite 3.49.1 (Ubuntu's 3.37.2 lacks `sqlite3_error_offset()`) | ~2 min |
| `08-boehm-gc.sh` | 8 | Builds Boehm GC 8.2.8 with C++ support | ~2 min |
| `09-curl.sh` | 9 | Builds libcurl 8.17.0 (Ubuntu has 7.81, too old) | ~5 min |
| `10-libgit2.sh` | 10 | Builds libgit2 1.9.0 (Ubuntu has 1.1, too old) | ~3 min |
| `11-libseccomp.sh` | 11 | Builds libseccomp 2.5.5 (Ubuntu has 2.5.3, too old) | ~2 min |
| `12-blake3.sh` | 12 | Builds BLAKE3 1.8.2 C library (not in Ubuntu) | ~1 min |
| `13-nix-build.sh` | 13 | Configures and compiles Nix with meson | ~10-20 min |
| `14-nix-install.sh` | 14 | Installs Nix, creates /nix/store, sets up nixbld users | ~2 min |
| `15-test-deps.sh` | 15 | Builds GoogleTest 1.15.2 and RapidCheck from source | ~5 min |
| `16-nix-build-tests.sh` | 16 | Reconfigures and rebuilds Nix with `-Dunit-tests=true` | ~10-20 min |
| `17-run-tests.sh` | 17 | Runs unit tests and functional test suites, saves logs | ~15-30 min |
| `18-verify-test-env.sh` | 18 | Diagnostic script: checks all test prerequisites, predicts failures | ~10 sec |

### Helper

| Script | Purpose |
|--------|---------|
| `sync-to-z.sh` | rsync helper to push Nix source, RapidCheck source, and scripts to `z` |

## Unit Test Details

| Suite | Tests | Pass | Fail | Time (s390x) |
|-------|------:|-----:|-----:|-------------|
| nix-util-tests | 693 | 693 | 0 | ~33s (RapidCheck PeekSort is slow) |
| nix-store-tests | 661 | 661 | 0 | ~2s |
| nix-expr-tests | 452 | 452 | 0 | ~3s |
| nix-fetchers-tests | 19 | 19 | 0 | <1s |
| nix-flake-tests | 21 | 21 | 0 | <1s |
| **Total** | **1,846** | **1,846** | **0** | ~38s |

All unit tests pass with patch 5 (sandbox ownership fix) applied. Without
this patch, 9 C API tests fail due to the sandbox rejecting build outputs
with group-writable permission bits.

**RapidCheck on s390x**: Upstream RapidCheck's static library is not built with
`-fPIC`. When linked into Nix's shared test-support libraries, text relocations
cause SIGSEGV on s390x. The fix is `CMAKE_POSITION_INDEPENDENT_CODE=ON` in
RapidCheck's build (applied in our [fork](https://github.com/randomizedcoder/rapidcheck/tree/nix-on-z)
and in `15-test-deps.sh`).

The `nix-util-tests` suite needs `-t 10` (10x timeout multiplier) because the
RapidCheck property-based sort tests are slow on s390x's 2 shared IFLs.

## Functional Test Details

109 pass / 2 fail / 16 skip out of 127 tests in the main suite.

The 16 skips are expected: tests for `busybox`, `macOS`, `help` rendering, and
features requiring infrastructure not present in a bare-metal bootstrap.

### Remaining 2 failures (upstream TODO_NixOS)

| Test | Line | Error | Root Cause |
|------|------|-------|-----------|
| structured-attrs.sh | 31 | `cannot find flake 'flake:nixpkgs'` | `nix develop` needs nixpkgs in the test's flake registry. Only populated on NixOS. Test has `TODO_NixOS` comment at line 25. |
| nested-sandboxing.sh | 5+ | build fails inside nested sandbox | Requires Nix's own dependencies to exist in `/nix/store`. Only true when Nix itself was installed from nixpkgs, not built from source. |

Both fail identically on x86_64 Ubuntu. Neither is s390x-specific.

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

## Low-Memory Considerations

The target machine has only 3.9 GiB RAM. GCC and Boost builds are limited to
`-j1` to avoid OOM kills during linking. All other builds use `-j$(nproc)`.

If GCC still OOMs at `-j1`, add swap:

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

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

We already have this in **Patch 1** (`__s390x__` for stack pointer and seccomp).

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

## License

MIT
