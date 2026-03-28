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
| **Unit tests** | 1,325 | 0 | 0 | 5 suites, all pass |
| **Functional tests** | 109 | 2 | 16 | 85.8% pass, 98.4% pass+skip |

The 2 remaining functional test failures are upstream `TODO_NixOS` issues that
fail identically on x86_64 Ubuntu:

- **structured-attrs.sh** -- `nix develop` needs `flake:nixpkgs` in the test's
  isolated flake registry, which is only populated on NixOS.
- **nested-sandboxing.sh** -- requires Nix's own dependencies in `/nix/store`,
  which only exists when Nix itself is installed from nixpkgs.

**No failures are s390x-specific.**

## Target Environment

| | |
|---|---|
| **Architecture** | s390x (IBM z16 / LinuxONE) |
| **OS** | Ubuntu 22.04 LTS |
| **RAM** | 3.9 GiB (scripts use `-j1` where needed to avoid OOM) |
| **Disk** | ~45 GB free recommended |
| **Nix version** | 2.35.0 (built from source) |

## Development Setup

The development workflow uses a local workstation to edit code and an SSH alias
to reach the remote s390x machine. Three repos live side-by-side on the
workstation:

```
~/Downloads/
    nix-on-z/          # this repo — bootstrap scripts + patches
    nix/               # NixOS/nix source (with patches applied)
    rapidcheck/        # randomizedcoder/rapidcheck fork (nix-on-z branch)
```

### SSH config

Add an entry to `~/.ssh/config` so that `ssh z` reaches the target machine:

```
Host z
  Hostname 148.100.85.239
  User linux1
```

The machine is an IBM LinuxONE Community Cloud instance running Ubuntu 22.04
on s390x with 2 IFLs and 3.9 GiB RAM.

### Syncing to the z machine

`sync-to-z.sh` pushes everything to the remote host in one command:

```bash
./sync-to-z.sh
```

This rsyncs three things to `z`:

| Local path | Remote path | What |
|---|---|---|
| `~/Downloads/nix/` | `z:nix/` | Patched Nix source (excludes `.git`, `build/`) |
| `~/Downloads/rapidcheck/` | `z:rapidcheck/` | RapidCheck fork with `-fPIC` fix |
| `nix-on-z/*.sh` | `z:nix-on-z/` | Bootstrap scripts, test scripts, patches |

On the remote machine, the layout is:

```
~/
    nix/               # Nix source tree (build happens here)
    nix-on-z/     # this repo (scripts + patches)
    rapidcheck/        # RapidCheck source (used by 15-test-deps.sh)
```

### Applying patches

Before the first sync, apply the patches to the local Nix source:

```bash
cd ~/Downloads/nix
git apply ../nix-on-z/patches/*.patch
```

## Quick Start

```bash
# On the target s390x machine (ssh z), run each phase in order:
cd ~/nix-on-z
sudo bash 00-apt-deps.sh
bash 01-meson-pip.sh
bash 02-gcc14.sh            # ~2-4 hours at -j1
source 03-env.sh
bash 04-boost.sh            # ~20-30 min at -j1
bash 05-nlohmann-json.sh
bash 06-toml11.sh
bash 07-sqlite.sh
bash 08-boehm-gc.sh
bash 09-curl.sh
bash 10-libgit2.sh
bash 11-libseccomp.sh
bash 12-blake3.sh
source 03-env.sh
cd ~/nix && bash ~/nix-on-z/13-nix-build.sh
bash ~/nix-on-z/14-nix-install.sh
nix --version               # nix (Nix) 2.35.0
```

Total time: ~3-5 hours (GCC 14 dominates).

## Running Tests

```bash
# Install test dependencies
bash 15-test-deps.sh         # GoogleTest, RapidCheck

# Rebuild with tests enabled
bash 16-nix-build-tests.sh

# Verify the environment first
bash 18-verify-test-env.sh

# Run tests
source 03-env.sh
cd ~/nix
meson test -C build -t 10   # all tests (unit + functional)
```

## Why So Many Dependencies From Source?

Ubuntu 22.04 is a stable LTS release, but Nix 2.35 requires C++23 and recent
versions of several libraries. Building GCC 14 from source gives us C++23
support, but it also creates a "split-world" problem: system libraries were
compiled with GCC 12, while Nix is compiled with GCC 14. This exposed
compatibility issues in 4 additional system packages that we also had to build
from source.

## Nix Source Patches

Four patches are needed. The first two add s390x support. The third and fourth
fix test infrastructure bugs that affect all non-NixOS systems.

### Patch 1: s390x architecture support

Two files in the Nix source tree need changes:

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

## Unit Test Details

| Suite | Tests | Result | Time (s390x) |
|-------|------:|--------|-------------|
| nix-util-tests | 130 | **PASS** | ~33s (RapidCheck PeekSort is slow) |
| nix-store-tests | 708 | **PASS** | ~2s |
| nix-expr-tests | 452 | **PASS** | ~3s |
| nix-fetchers-tests | 18 | **PASS** | <1s |
| nix-flake-tests | 17 | **PASS** | <1s |
| **Total** | **1,325** | **PASS** | ~38s |

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

## Verification

```bash
$ nix --version
nix (Nix) 2.35.0

$ nix --extra-experimental-features nix-command store info
Store URL: local
Version: 2.35.0
Trusted: 1

$ nix --extra-experimental-features nix-command eval --expr '1 + 1'
2
```

## License

MIT
