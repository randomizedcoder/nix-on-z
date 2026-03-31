[< Patches overview](../patches.md) | [< README](../../README.md)

# Patch 3: Add `$shell` test variable

**Files:** `tests/functional/common/subst-vars.sh.in`, `tests/functional/common/vars.sh`

**Category:** all platforms

Several functional tests (`formatter.sh`, `nix-profile.sh`) use `${shell}` in
heredocs to create derivation build scripts. This variable was never defined in
the test infrastructure for non-NixOS systems, causing "unbound variable"
failures.

**Fix:** add `shell=@bash@` to `tests/functional/common/subst-vars.sh.in` and
export it from `vars.sh`.
