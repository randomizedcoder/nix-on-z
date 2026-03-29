[< Patches overview](../patches.md) | [< README](../../README.md)

# Patch 4: Fix recursive git submodule transport

**File:** `tests/functional/fetchGitSubmodules.sh`

**Category:** all platforms

`fetchGitSubmodules.sh` fails on the nested submodule test because
`GIT_CONFIG_COUNT` environment variables do not propagate through recursive
`git submodule update` helper processes on older git versions (e.g., 2.34.1).

**Fix:** use `git -c protocol.file.allow=always` instead of relying on
`GIT_CONFIG_COUNT` environment variables. The `-c` flag sets
`GIT_CONFIG_PARAMETERS` which does propagate to recursive subprocesses.
