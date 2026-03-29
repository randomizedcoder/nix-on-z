[< Back to README](../README.md)

# Nix Source Patches

Seven patches are required. Two add s390x architecture support. Five fix test
infrastructure bugs that affect all platforms (not s390x-specific). Patches
are applied to a clean checkout of [NixOS/nix](https://github.com/NixOS/nix)
master.

## Summary

| Patch | File(s) | Category | Summary |
|-------|---------|----------|---------|
| 0001 | `stack.cc`, `linux-derivation-builder.cc` | s390x | Architecture detection: stack pointer + seccomp |
| 0002 | `vars.sh` | all platforms | Fix unbound `$NIX_STORE` variable |
| 0003 | `subst-vars.sh.in`, `vars.sh` | all platforms | Add missing `$shell` test variable |
| 0004 | `fetchGitSubmodules.sh` | all platforms | Fix recursive git submodule transport |
| 0005 | `derivation-builder.cc` | all platforms | Fix sandbox ownership check for non-root builds |
| 0006 | `develop.cc` | all platforms | Fix `nix develop -f` structured attrs + flake registry |
| 0007 | `nested-sandboxing.sh` | all platforms | Fix skip check for empty `/nix/store` |

## Patch details

### [Patch 1: s390x architecture support](patches/0001-add-s390x-support.md)

Adds s390x stack pointer register (R15) for the SIGSEGV stack overflow detector
and the 31-bit s390 compat architecture for the seccomp sandbox filter.

### [Patch 2: Fix unbound NIX_STORE variable](patches/0002-fix-unbound-nix-store.md)

On non-NixOS systems, `NIX_STORE` is not set. The bare `$NIX_STORE` reference
causes "unbound variable" errors under `set -u`, failing all functional tests.

### [Patch 3: Add `$shell` test variable](patches/0003-add-shell-test-variable.md)

Several functional tests use `${shell}` in heredocs but the variable was never
defined in the test infrastructure for non-NixOS systems.

### [Patch 4: Fix recursive git submodule transport](patches/0004-fix-fetchGitSubmodules-transport.md)

`GIT_CONFIG_COUNT` environment variables do not propagate through recursive
`git submodule update` on older git versions. Uses `git -c` flag instead.

### [Patch 5: Fix sandbox ownership check](patches/0005-fix-sandbox-ownership-check.md)

Gates the group/world-writable permission check on `buildUser` being non-null,
fixing 9 C API test failures in non-root builds.

### [Patch 6: Fix `nix develop` structured attrs](patches/0006-fix-nix-develop-structured-attrs.md)

Fixes two interacting bugs: a spurious flake registry lookup in non-flake mode
and missing individual output variables (`$out`, `$dev`) for structured attrs.

### [Patch 7: Fix nested-sandboxing skip check](patches/0007-fix-nested-sandboxing-skip.md)

Replaces the directory-existence check with a content check that verifies
`/nix/store` is actually populated, correctly skipping on bootstrap installations.

## Patch validation

All patches verified on the actual s390x machine. Key validations:
- **Patch 5** (sandbox ownership): 0 unit test failures (was 9 without it)
- **Patch 6** (structured-attrs): `structured-attrs.sh` passes (was failing)
- **Patch 7** (nested-sandboxing): correctly SKIPs (was failing)
