[< Patches overview](../patches.md) | [< README](../../README.md)

# Patch 2: Fix unbound NIX_STORE variable

**File:** `tests/functional/common/vars.sh`

**Category:** all platforms

On non-NixOS systems, `NIX_STORE` is not set. With bash's `set -u` (nounset),
the bare `$NIX_STORE` reference in `tests/functional/common/vars.sh` causes an
"unbound variable" error, making all functional tests fail.

**Fix:** `$NIX_STORE` -> `${NIX_STORE-}` (default to empty when unset).
