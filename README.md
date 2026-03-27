# nix-on-z

Bootstrapping [Nix](https://github.com/NixOS/nix) on IBM Z (s390x) from source.

This repo contains everything needed to build and install Nix on an IBM
LinuxONE / z machine running Ubuntu 22.04. The upstream Nix codebase does not
yet ship s390x support, and Ubuntu 22.04's packages are too old for several
dependencies. We solve both problems: two small code patches add s390x arch
support, and a set of numbered shell scripts build the missing dependencies
from source, then configure, build, and install Nix itself.

## Target Environment

| | |
|---|---|
| **Architecture** | s390x (IBM z16 / LinuxONE) |
| **OS** | Ubuntu 22.04 LTS |
| **RAM** | 3.9 GiB (scripts use `-j1` where needed to avoid OOM) |
| **Disk** | ~45 GB free recommended |
| **Nix version** | 2.35.0 (built from source) |

## Quick Start

```bash
# Clone this repo and the Nix source
git clone https://github.com/randomizedcoder/nix-on-z.git
git clone https://github.com/NixOS/nix.git

# Apply the s390x patches to the Nix source
cd nix
git apply ../nix-on-z/patches/0001-add-s390x-support.patch
cd ..

# Copy scripts to the target machine (edit sync-to-z.sh for your host)
# Or just scp the scripts and nix source directly

# On the target s390x machine, run each phase in order:
cd ~/nix-bootstrap
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
cd ~/nix && bash ~/nix-bootstrap/13-nix-build.sh
bash ~/nix-bootstrap/14-nix-install.sh
nix --version               # nix (Nix) 2.35.0
```

Total time: ~3-5 hours (GCC 14 dominates).

## Why So Many Dependencies From Source?

Ubuntu 22.04 is a stable LTS release, but Nix 2.35 requires C++23 and recent
versions of several libraries. Building GCC 14 from source gives us C++23
support, but it also creates a "split-world" problem: system libraries were
compiled with GCC 12, while Nix is compiled with GCC 14. This exposed
compatibility issues in 4 additional system packages that we also had to build
from source.

## Nix Source Patches

Only **two files** in the Nix source tree need changes for s390x. Both are
minimal and follow existing patterns for other architectures. The combined
patch is in `patches/0001-add-s390x-support.patch`.

### 1. Stack pointer detection (`src/libmain/unix/stack.cc`)

Adds s390x stack pointer register (R15 = `gregs[15]`) for the SIGSEGV stack
overflow detector:

```cpp
#elif defined(__s390x__)
    sp = (char *) ((ucontext_t *) ctx)->uc_mcontext.gregs[15];
```

### 2. Seccomp architecture (`src/libstore/unix/build/linux-derivation-builder.cc`)

Adds the 31-bit s390 compat architecture for the seccomp sandbox filter,
following the existing pattern for aarch64/ARM and x86_64/x86:

```cpp
if (nativeSystem == "s390x-linux" && seccomp_arch_add(ctx, SCMP_ARCH_S390) != 0)
    printError("unable to add s390 seccomp architecture");
```

## Scripts

Each script is self-contained, idempotent (safe to re-run), and prints a
completion message on success. They install everything into `/usr/local`.

| Script | Phase | What it does | Time |
|--------|-------|-------------|------|
| `00-apt-deps.sh` | 0 | Installs Ubuntu packages (ninja, cmake, pkg-config, etc.) | ~2 min |
| `01-meson-pip.sh` | 1 | Installs meson >= 1.1 via pip (Ubuntu ships 0.61) | ~1 min |
| `02-gcc14.sh` | 2 | Builds GCC 14.2.0 from source for C++23 support | ~2-4 hrs |
| `03-env.sh` | 3 | Sets CC, CXX, PATH, LD_LIBRARY_PATH, PKG_CONFIG_PATH (source, don't execute) | — |
| `04-boost.sh` | 4 | Builds Boost 1.87.0 (Ubuntu has 1.74, too old) | ~20-30 min |
| `05-nlohmann-json.sh` | 5 | Installs nlohmann_json 3.11.3 (Ubuntu's 3.10.5 fails with GCC 14) | ~1 min |
| `06-toml11.sh` | 6 | Installs toml11 4.4.0 (Ubuntu's apt pkg lacks cmake config files) | ~1 min |
| `07-sqlite.sh` | 7 | Builds SQLite 3.49.1 (Ubuntu's 3.37.2 lacks `sqlite3_error_offset()`) | ~2 min |
| `08-boehm-gc.sh` | 8 | Builds Boehm GC 8.2.8 with C++ support (Ubuntu's 8.0.6 has private `value_type` bug) | ~2 min |
| `09-curl.sh` | 9 | Builds libcurl 8.17.0 (Ubuntu has 7.81, Nix requires >= 8.17) | ~5 min |
| `10-libgit2.sh` | 10 | Builds libgit2 1.9.0 (Ubuntu has 1.1, too old) | ~3 min |
| `11-libseccomp.sh` | 11 | Builds libseccomp 2.5.5 (Ubuntu has 2.5.3, too old) | ~2 min |
| `12-blake3.sh` | 12 | Builds BLAKE3 1.8.2 C library (not in Ubuntu) | ~1 min |
| `13-nix-build.sh` | 13 | Configures and compiles Nix with meson | ~10-20 min |
| `14-nix-install.sh` | 14 | Installs Nix, creates /nix/store, sets up nixbld users | ~2 min |

### Helper

| Script | Purpose |
|--------|---------|
| `sync-to-z.sh` | rsync helper to push Nix source and scripts to a remote s390x machine |

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

The Nix build uses these non-default meson options:

```
-Dlibcmd:readline-flavor=readline   # editline not available on Ubuntu 22.04
-Ddoc-gen=false                     # skip documentation generation
-Dunit-tests=false                  # skip test compilation
-Dbindings=false                    # skip Perl bindings
-Dbenchmarks=false                  # skip benchmarks
-Djson-schema-checks=false          # skip JSON schema validation
```

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
