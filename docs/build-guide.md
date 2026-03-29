[< Back to README](../README.md)

# Build Guide

## Prerequisites

1. An s390x machine running Ubuntu 22.04 (e.g., IBM LinuxONE Community Cloud)
2. A local workstation with SSH access to the s390x machine
3. A fork or clone of [NixOS/nix](https://github.com/NixOS/nix)

## Step 1: Clone the repos

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

## Step 2: Apply patches

```bash
cd ~/Downloads/nix
git apply ../nix-on-z/patches/*.patch
```

Or apply individually:

```bash
git apply ../nix-on-z/patches/0001-add-s390x-support.patch
git apply ../nix-on-z/patches/0002-fix-functional-tests-unbound-NIX_STORE.patch
git apply ../nix-on-z/patches/0003-add-shell-test-variable.patch
git apply ../nix-on-z/patches/0004-fix-fetchGitSubmodules-recursive-transport.patch
git apply ../nix-on-z/patches/0005-fix-sandbox-ownership-check-non-root.patch
git apply ../nix-on-z/patches/0006-fix-nix-develop-structured-attrs-outputs.patch
git apply ../nix-on-z/patches/0007-fix-nested-sandboxing-skip-check.patch
```

Verify patches applied correctly:

```bash
grep '__s390x__' src/libmain/unix/stack.cc                        # Patch 1
grep 'NIX_STORE-' tests/functional/common/vars.sh                 # Patch 2
grep '^shell=' tests/functional/common/subst-vars.sh.in           # Patch 3
grep 'protocol.file.allow=always' tests/functional/fetchGitSubmodules.sh  # Patch 4
grep 'buildUser' src/libstore/unix/build/derivation-builder.cc | grep -c 'if (buildUser'  # Patch 5
grep 'flakeInstallable' src/nix/develop.cc                        # Patch 6
grep 'ls -A /nix/store' tests/functional/nested-sandboxing.sh     # Patch 7
```

## Step 3: Configure SSH

Add an entry to `~/.ssh/config` so `ssh z` reaches the target machine:

```
Host z
  Hostname <your-s390x-ip>
  User <your-username>
```

## Step 4: Sync to the s390x machine

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

## Step 5: Build everything on the s390x machine

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

## Step 6: Run tests

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

Expected results: 1,932 unit tests pass, 178/0/30 functional pass/fail/skip.

## Step 7: Verify

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
