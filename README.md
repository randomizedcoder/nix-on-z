# nix-on-z

Bootstrapping [Nix](https://github.com/NixOS/nix) on IBM Z (s390x) from source.

This repo contains everything needed to build and install Nix on an IBM
LinuxONE / z machine running Ubuntu 22.04. The upstream Nix codebase does not
yet ship s390x support, and Ubuntu 22.04's packages are too old for several
dependencies. We solve both problems: small code patches add s390x arch
support, and a Nix flake generates the bootstrap scripts that build the
missing dependencies from source, then configure, build, and install Nix itself.

## Status

| | Pass | Fail | Skip |
|---|---:|---:|---:|
| **Unit tests** | 1,932 | 0 | 0 |
| **Functional tests** | 183 | 0 | 30 |

**All tests pass.** See [detailed test results](docs/testing.md).

## Documentation

| Document | Description |
|----------|-------------|
| [Patches](docs/patches.md) | Eight patches for s390x support and test fixes, with root cause analysis |
| [Testing](docs/testing.md) | Full test results, sandbox shell setup, and config.nix details |
| [Build Guide](docs/build-guide.md) | Step-by-step reproduction: clone, patch, build, test, verify |
| [S390X Porting Guide](S390X-PORTING-GUIDE.md) | Master guide for porting nixpkgs packages to s390x |
| [Priority Plan](docs/priority-plan.md) | Dependency-graph-ranked porting priorities |
| [ClickHouse Case Study](docs/example-clickhouse.md) | End-to-end porting example |
| [Technical Reference](docs/technical-reference.md) | s390x architecture reference (replaces s390x-analysis.md) |
| [Package Cross-Reference](docs/package-crossref.md) | 353 linux-on-ibm-z repos mapped to nixpkgs |
| [IBM Z Patch Reuse](docs/ibm-z-patch-reuse.md) | Prioritized strategy for reusing linux-on-ibm-z patches |

## Architecture

The bootstrap scripts are defined in Nix and generated as derivations, making
Nix the single source of truth for the entire build pipeline.

Originally, the project used hand-written shell scripts in a `scripts/`
directory. These were migrated to Nix using `writeShellApplication` (for
shellcheck validation at build time) and `writeTextFile` (for z-deployable
scripts with `#!/usr/bin/env bash` shebangs). This dual-output approach gives
us the best of both worlds: Nix-level validation and reproducibility, plus
scripts that run on z without a Nix store.

```
nix/
  z-scripts.nix              # mkZScript builder + all 18 script definitions
  z-scripts/
    versions.nix              # Pinned dependency versions/URLs (single source of truth)
    env.nix                   # Shared env setup (CC, CXX, PATH, PKG_CONFIG_PATH)
```

Each script produces two outputs:
- **`check`** -- `writeShellApplication` derivation (shellcheck at build time via `nix flake check`)
- **`script`** -- `writeTextFile` with portable `#!/usr/bin/env bash` shebang (runs on z)

Version strings, URLs, and environment setup are centralized in `versions.nix`
and `env.nix`, eliminating duplication across scripts.

## Patches

Eight patches are required. Two add s390x architecture support. Six fix test
infrastructure bugs that affect all platforms (not s390x-specific).

| Patch | File(s) | Category | Summary |
|-------|---------|----------|---------|
| 0001 | `stack.cc`, `linux-derivation-builder.cc` | s390x | Architecture detection: stack pointer + seccomp |
| 0002 | `vars.sh` | all platforms | Fix unbound `$NIX_STORE` variable |
| 0003 | `subst-vars.sh.in`, `vars.sh` | all platforms | Add missing `$shell` test variable |
| 0004 | `fetchGitSubmodules.sh` | all platforms | Fix recursive git submodule transport |
| 0005 | `derivation-builder.cc` | all platforms | Fix sandbox ownership check for non-root builds |
| 0006a | `develop.cc` | all platforms | Fix `nix develop` structured attrs output variables |
| 0006b | `develop.cc` | all platforms | Fix `nix develop -f` non-flake bashInteractive lookup |
| 0007 | `nested-sandboxing.sh` | all platforms | Fix skip check for empty `/nix/store` |

Details: [docs/patches.md](docs/patches.md)

## Quick Start

### With Nix flake (recommended)

```bash
# Cross-compile for s390x from your workstation
nix build .#nix-s390x
file result/bin/nix  # ELF 64-bit MSB executable, IBM S/390

# Or: prepare source + sync to z for native build
nix run .#sync            # rsync patched source + generated scripts to z
nix run .#build-remote    # build on z via ssh
nix run .#test-remote     # run tests on z

# Dev shell with tools
nix develop

# Verify patches + per-script shellcheck
nix flake check
```

### Without Nix (manual)

The generated scripts are included in the source bundle. You can also build
the bundle locally and copy the scripts:

```bash
nix build .#source-bundle
ls result/scripts/         # all 18 generated scripts
scp result/scripts/*.sh z:nix-on-z/
```

Or clone and build manually on z -- see [docs/build-guide.md](docs/build-guide.md).

## Target Environment

All machines are provided by the [LinuxONE Community Cloud](https://developer.ibm.com/articles/get-started-with-ibm-linuxone/).

| | **z** (original) | **z2** (current) |
|---|---|---|
| **Role** | Initial bootstrap & testing | Primary build server |
| **Machine type** | 8561 (z15) | 8561 (z15) |
| **vCPUs** | 2 | 4 |
| **RAM** | 3.9 GiB | 15 GiB |
| **Disk** | 50 GB | 99 GB |
| **OS** | Ubuntu 22.04.5 LTS | Ubuntu 22.04.1 LTS |
| **Clock** | 5.2 GHz | 5.2 GHz |
| **L1 cache** | 128KB I + 128KB D / core | 128KB I + 128KB D / core |
| **L2 cache** | 4MB / core | 4MB / core |
| **L3 cache** | 256MB shared | 256MB shared |
| **L4 cache** | 960MB shared | 960MB shared |
| **Nix version** | 2.35.0 (built from source) | 2.35.0 (building) |
| **SSH alias** | `z` | `z2` |

**Why z2?** The original z machine (2 vCPU, 4GB RAM, 50GB disk) is too small
for bootstrapping LLVM/Clang from source — the `libclang-cpp.so` link step
needs 7+ GB RAM, and the nix store + build artifacts exceed 50GB. z2 has 4x
the RAM, 2x the cores, and 2x the disk — enough for a full nixpkgs bootstrap.

All deploy scripts support `Z_HOST=z2` to target the new machine:
```bash
Z_HOST=z2 nix run .#sync           # sync source to z2
Z_HOST=z2 nix run .#build-remote   # build nix on z2
Z_HOST=z2 nix run .#tune-ubuntu    # apply OS tuning to z2
```

## License

MIT
