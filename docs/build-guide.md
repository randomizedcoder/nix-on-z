[< Back to README](../README.md)

# Build Guide

## Prerequisites

1. An s390x machine running Ubuntu 22.04 (e.g., IBM LinuxONE Community Cloud)
2. A local workstation with SSH access to the s390x machine
3. Nix installed on your workstation (for the flake workflow)

## Option A: Nix Flake Workflow (Recommended)

The flake generates all bootstrap scripts from Nix definitions, bundles them
with the patched Nix source, and provides deployment apps. This is the
simplest and most reproducible approach.

### Step 1: Clone

```bash
git clone https://github.com/randomizedcoder/nix-on-z.git
cd nix-on-z
```

### Step 2: Configure SSH

Add an entry to `~/.ssh/config` so `ssh z` reaches the target machine:

```
Host z
  Hostname <your-s390x-ip>
  User <your-username>
```

### Step 3: Sync to the s390x machine

```bash
nix run .#sync
```

This builds the source bundle (patching Nix source, generating all 18
bootstrap scripts from `nix/z-scripts.nix`) and rsyncs to z:

| Remote path | What |
|---|---|
| `z:nix/` | Patched Nix 2.35.0 source |
| `z:rapidcheck/` | RapidCheck fork with `-fPIC` fix |
| `z:nix-on-z/*.sh` | Generated bootstrap scripts |
| `z:nix-on-z/patches/` | Patch files |

### Step 4: Build on z

```bash
# Automated (runs all build scripts in order via SSH)
nix run .#build-remote

# Or manual (SSH in and run individually)
ssh z
cd ~/nix-on-z
sudo bash 00-apt-deps.sh    # system packages
bash 01-meson-pip.sh         # meson via pip
bash 02-gcc14.sh             # GCC 14 (~2-4 hours at -j1)
bash 04-boost.sh             # Boost 1.87 (~20-30 min at -j1)
bash 05-nlohmann-json.sh     # nlohmann_json 3.11.3
bash 06-toml11.sh            # toml11 4.4.0
bash 07-sqlite.sh            # SQLite 3.49.1
bash 08-boehm-gc.sh          # Boehm GC 8.2.8
bash 09-curl.sh              # libcurl 8.17.0
bash 10-libgit2.sh           # libgit2 1.9.0
bash 11-libseccomp.sh        # libseccomp 2.5.5
bash 12-blake3.sh            # BLAKE3 1.8.2
bash 13-nix-build.sh         # configure + compile Nix
bash 14-nix-install.sh       # install Nix + setup /nix/store
nix --version                # nix (Nix) 2.35.0
```

Note: scripts 04-14 have the environment setup (CC, CXX, PATH, etc.) inlined
-- there is no need to manually `source 03-env.sh` before each one.
`03-env.sh` is still generated for interactive use on z.

Total time: ~3-5 hours (GCC 14 dominates).

### Step 5: Run tests

```bash
# Automated
nix run .#test-remote

# Or manual
ssh z
cd ~/nix-on-z
bash 15-test-deps.sh          # GoogleTest, RapidCheck, jq
bash 16-nix-build-tests.sh    # rebuild with -Dunit-tests=true
bash 18-verify-test-env.sh    # check prerequisites (should exit 0)
bash 17-run-tests.sh          # run unit + functional suites
```

Expected results: 1,932 unit tests pass, 183/0/30 functional pass/fail/skip.

### Step 6: Verify

```bash
ssh z
nix --version
# nix (Nix) 2.35.0

nix --extra-experimental-features nix-command store info
# Store URL: local

nix --extra-experimental-features nix-command eval --expr '1 + 1'
# 2
```

### Validate locally

```bash
# Per-script shellcheck + patch verification
nix flake check

# Build source bundle and inspect generated scripts
nix build .#source-bundle
ls result/scripts/
diff <(cat result/scripts/07-sqlite.sh) <(echo "expected content...")
```

## Option B: Manual Workflow (Without Nix on Workstation)

If you don't have Nix on your workstation, you can build the source bundle
scripts manually or clone the repos directly.

### Step 1: Clone the repos

```bash
cd ~/Downloads

# This repo
git clone https://github.com/randomizedcoder/nix-on-z.git

# NixOS/nix source
git clone https://github.com/randomizedcoder/nix.git
cd nix && git checkout origin/master && cd ..

# RapidCheck fork with -fPIC fix for s390x
git clone -b nix-on-z https://github.com/randomizedcoder/rapidcheck.git
```

### Step 2: Apply patches

```bash
cd ~/Downloads/nix
git apply ../nix-on-z/patches/*.patch
```

### Step 3: Sync and build

You'll need to sync the source and scripts to z manually with rsync, then
follow the same build steps as Option A Step 4 above.

## Script Design

The bootstrap scripts were originally hand-written shell scripts in a
`scripts/` directory. They have been migrated to Nix definitions in
`nix/z-scripts.nix`, which generates each script as a Nix derivation.

Each script is defined as `{ name, text, needsEnv }` and produces:

- **`check`**: `writeShellApplication` -- shellcheck validation at build time
- **`script`**: `writeTextFile` -- portable `#!/usr/bin/env bash` for z

Scripts with `needsEnv = true` have the environment setup (GCC 14 paths,
pkg-config, Boost) inlined from `nix/z-scripts/env.nix`, eliminating the
need to manually source `03-env.sh`.

All dependency versions and URLs are centralized in `nix/z-scripts/versions.nix`.

Every script is idempotent (safe to re-run) and has version guards that skip
if the correct version is already installed.

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

Each script is generated from `nix/z-scripts.nix`, shellcheck-validated via
`nix flake check`, idempotent (safe to re-run), and prints a completion
message on success. They install everything into `/usr/local`.

| Script | Phase | What it does | Time |
|--------|-------|-------------|------|
| `00-apt-deps.sh` | 0 | Installs Ubuntu packages, removes busybox-static, installs bash-static | ~2 min |
| `01-meson-pip.sh` | 1 | Installs meson >= 1.1 via pip (Ubuntu ships 0.61) | ~1 min |
| `02-gcc14.sh` | 2 | Builds GCC 14.2.0 from source for C++23 support | ~2-4 hrs |
| `03-env.sh` | 3 | Sets CC, CXX, PATH, LD_LIBRARY_PATH, PKG_CONFIG_PATH (for interactive use) | -- |
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
| `15-test-deps.sh` | 15 | Builds jq 1.7.1, GoogleTest 1.15.2, and RapidCheck from source | ~5 min |
| `16-nix-build-tests.sh` | 16 | Reconfigures and rebuilds Nix with `-Dunit-tests=true` | ~10-20 min |
| `17-run-tests.sh` | 17 | Runs unit tests and functional test suites, saves logs | ~15-30 min |
| `18-verify-test-env.sh` | 18 | Diagnostic script: checks all test prerequisites, predicts failures | ~10 sec |

## Flake Apps

| App | Purpose |
|-----|---------|
| `nix run .#sync` | Build source bundle and rsync patched source + generated scripts to z |
| `nix run .#build-remote` | SSH to z and run build scripts 00-14 in order |
| `nix run .#test-remote` | SSH to z and run test scripts 15-17 in order |

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
