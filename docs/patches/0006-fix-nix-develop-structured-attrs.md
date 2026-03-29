[< Patches overview](../patches.md) | [< README](../../README.md)

# Patch 6: Fix `nix develop -f` structured attrs and flake registry lookup

**File:** `src/nix/develop.cc`

**Category:** all platforms

`nix develop` always tries to find `bashInteractive` from nixpkgs to provide
a better interactive shell, even when the user passes `-f` (file mode, not
flake mode). Two bugs interact here:

## Bug 1 -- Spurious flake registry lookup

In `src/nix/develop.cc` (line 648), the code calls `defaultNixpkgsFlakeRef()`
which returns `flake:nixpkgs` -- an indirect flake reference requiring a flake
registry. When the installable is created via `-f`, it's an
`InstallableAttrPath`, not an `InstallableFlake`. The `dynamic_cast` at line 649
fails, so it falls back to the default `flake:nixpkgs` lookup. This always fails
in the test harness because tests use an isolated empty flake registry
(`flake-registry = $TEST_ROOT/registry.json` in `common/init.sh`). The error is
silently caught (lines 675-677) but leaves the shell environment in a broken
state.

## Bug 2 -- Missing individual output variables for structured attrs

With structured attrs (`__structuredAttrs = true`), output paths are stored in a
bash associative array (`declare -A outputs=([out]='...' [dev]='...')`).
The `toBash()` method in `develop.cc` emits this array, but does NOT emit
individual variables like `$out` and `$dev`. Normally, Nix's `stdenv/setup.sh`
extracts these from the array at build time, but `nix develop` skips stdenv
and sources the environment directly. The test at `structured-attrs.sh:31`
(`test -n "$out"`) fails because `$out` is never set.

## Fix (two parts)

1. Skip the bashInteractive lookup entirely when the installable is not a
   flake (`InstallableFlake`). For non-flake mode, fall back directly to
   system bash without attempting flake registry resolution.
2. When emitting structured attrs outputs, also export individual variables
   (`out`, `dev`, etc.) from the associative array, matching what `stdenv`
   would do at build time.
