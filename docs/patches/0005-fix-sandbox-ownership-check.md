[< Patches overview](../patches.md) | [< README](../../README.md)

# Patch 5: Fix sandbox ownership check for non-root builds

**File:** `src/libstore/unix/build/derivation-builder.cc`

**Category:** all platforms

The sandbox output validation in `src/libstore/unix/build/derivation-builder.cc`
unconditionally rejects build outputs with group-writable or world-writable
permission bits. This check is designed for builds running as root with
dedicated build users, where group/world-writable files indicate potential
tampering.

However, when running as a non-root user (the common case for unit tests and
development builds), there are no build users -- the builder runs as the calling
user with the caller's umask. A standard Ubuntu umask of `0002` creates files
with group-writable bits (`0664`), which triggers the rejection even though no
security concern exists. The permission bits are canonicalised immediately after
the check anyway.

**Fix:** gate the group/world-writable permission check on `buildUser` being
non-null, matching the existing UID ownership check which is already gated.
This fixes 9 C API test failures (`nix_api_store_test`, `nix_api_expr_test`)
that build derivations inside the test harness.
