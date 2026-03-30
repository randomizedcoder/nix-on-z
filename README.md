# nix-on-z

Bootstrapping [Nix](https://github.com/NixOS/nix) on IBM Z (s390x) from source.

This repo contains everything needed to build and install Nix on an IBM
LinuxONE / z machine running Ubuntu 22.04. The upstream Nix codebase does not
yet ship s390x support, and Ubuntu 22.04's packages are too old for several
dependencies. We solve both problems: small code patches add s390x arch
support, and a set of numbered shell scripts build the missing dependencies
from source, then configure, build, and install Nix itself.

## Status

| | Pass | Fail | Skip |
|---|---:|---:|---:|
| **Unit tests** | 1,932 | 0 | 0 |
| **Functional tests** | 178 | 0 | 30 |

**All tests pass.** See [detailed test results](docs/testing.md).

## Documentation

| Document | Description |
|----------|-------------|
| [Patches](docs/patches.md) | Seven patches for s390x support and test fixes, with root cause analysis |
| [Testing](docs/testing.md) | Full test results, sandbox shell setup, and config.nix details |
| [Build Guide](docs/build-guide.md) | Step-by-step reproduction: clone, patch, build, test, verify |
| [s390x Analysis](docs/s390x-analysis.md) | Endianness analysis and IBM porting patterns for nixpkgs |

## Patches

Seven patches are required. Two add s390x architecture support. Five fix test
infrastructure bugs that affect all platforms (not s390x-specific).

| Patch | File(s) | Category | Summary |
|-------|---------|----------|---------|
| 0001 | `stack.cc`, `linux-derivation-builder.cc` | s390x | Architecture detection: stack pointer + seccomp |
| 0002 | `vars.sh` | all platforms | Fix unbound `$NIX_STORE` variable |
| 0003 | `subst-vars.sh.in`, `vars.sh` | all platforms | Add missing `$shell` test variable |
| 0004 | `fetchGitSubmodules.sh` | all platforms | Fix recursive git submodule transport |
| 0005 | `derivation-builder.cc` | all platforms | Fix sandbox ownership check for non-root builds |
| 0006 | `develop.cc` | all platforms | Fix `nix develop -f` structured attrs + flake registry |
| 0007 | `nested-sandboxing.sh` | all platforms | Fix skip check for empty `/nix/store` |

Details: [docs/patches.md](docs/patches.md)

## Quick Start

### With Nix flake (recommended)

```bash
# Cross-compile for s390x from your workstation
nix build .#nix-s390x
file result/bin/nix  # ELF 64-bit MSB executable, IBM S/390

# Or: prepare source + sync to z for native build
nix run .#sync            # rsync patched source to z
nix run .#build-remote    # build on z via ssh
nix run .#test-remote     # run tests on z

# Dev shell with tools
nix develop

# Verify patches + shellcheck
nix flake check
```

### Without Nix (manual)

```bash
# Clone repos
git clone https://github.com/randomizedcoder/nix-on-z.git
git clone https://github.com/randomizedcoder/nix.git
git clone -b nix-on-z https://github.com/randomizedcoder/rapidcheck.git

# Apply patches
cd nix && git apply ../nix-on-z/patches/*.patch && cd ..

# Sync to s390x machine and build
cd nix-on-z && bash scripts/sync-to-z.sh
ssh z 'cd ~/nix-on-z && sudo bash 00-apt-deps.sh && bash 01-meson-pip.sh && bash 02-gcc14.sh'
ssh z 'source ~/nix-on-z/03-env.sh && cd ~/nix-on-z && for s in 04 05 06 07 08 09 10 11 12; do bash ${s}-*.sh; done'
ssh z 'source ~/nix-on-z/03-env.sh && cd ~/nix && bash ~/nix-on-z/13-nix-build.sh && bash ~/nix-on-z/14-nix-install.sh'

# Verify
ssh z 'nix --version'  # nix (Nix) 2.35.0
```

Full instructions: [docs/build-guide.md](docs/build-guide.md)

## Target Environment

| | |
|---|---|
| **Architecture** | s390x (IBM z16 / LinuxONE) |
| **OS** | Ubuntu 22.04 LTS |
| **RAM** | 3.9 GiB (scripts use `-j1` where needed to avoid OOM) |
| **Disk** | ~45 GB free recommended |
| **Nix version** | 2.35.0 (built from source) |

## License

MIT
