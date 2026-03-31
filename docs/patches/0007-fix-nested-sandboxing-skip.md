[< Patches overview](../patches.md) | [< README](../../README.md)

# Patch 7: Fix nested-sandboxing skip check for empty `/nix/store`

**File:** `tests/functional/nested-sandboxing.sh`

**Category:** all platforms

The `nested-sandboxing.sh` test runs recursive nix-builds at multiple nesting
levels, each inside its own sandbox. This requires a populated `/nix/store`
with Nix's runtime dependencies (bash, coreutils) because `config.nix`
references these paths as the builder shell and PATH.

The skip check at line 5 only tests for directory existence:
```bash
[[ -d /nix/store ]] || skipTest "..."
```

On a bootstrap installation (like nix-on-z), `/nix/store` exists but is empty.
The test proceeds and then fails because:
- `config.nix` sets `shell = "/usr/bin/bash"` (the system bash)
- Inside the sandbox chroot, only `/bin/sh` (the sandbox shell) exists
- The builder tries to execute `/usr/bin/bash` which doesn't exist in the chroot
- This causes `error: executing '/usr/bin/bash': No such file or directory`
- The error message doesn't match the expected `` `sandbox-build-dir` must not
  contain `` pattern, so the `grepQuiet` at line 24 fails

## Fix

Replace the directory-existence check with a content check that verifies
`/nix/store` is actually populated:
```bash
if [[ ! -d /nix/store ]] || [[ -z "$(ls -A /nix/store 2>/dev/null)" ]]; then
    skipTest "nested sandboxing requires a populated /nix/store with Nix's runtime dependencies"
fi
```

This follows the existing pattern of prerequisite checks (`requireSandboxSupport`,
`requireGit`, etc.) and correctly skips on bootstrap installations while still
running on NixOS where `/nix/store` is fully populated.
