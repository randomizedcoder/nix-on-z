# Contributing Patches Upstream

[Back to overview](../S390X-PORTING-GUIDE.md)

---

## Nixpkgs PR Workflow

1. Fork nixpkgs and create a branch: `s390x/<package-name>`
2. Make the s390x-specific change (see [Nix Patterns](nix-patterns.md) for recipes)
3. Test with: `nix build .#pkgsCross.s390x.<package>`
4. Submit PR with title: `<package>: add s390x support`
5. Reference this guide and any linux-on-ibm-z patches used

## Using `fetchpatch` from linux-on-ibm-z

When a linux-on-ibm-z repo has a patch that upstream hasn't merged:

```nix
patches = lib.optionals stdenv.hostPlatform.isS390x [
  (fetchpatch {
    name = "s390x-support.patch";
    url = "https://github.com/linux-on-ibm-z/<repo>/commit/<sha>.patch";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  })
];
```

**Important:** Always check if the patch has been merged upstream first. If it has,
the package may just need a version bump rather than a patch.

## When to Patch Upstream vs in Nixpkgs

| Situation | Action |
|-----------|--------|
| Bug exists in latest upstream release | Patch in nixpkgs with `fetchpatch`, submit upstream PR |
| Bug fixed in upstream Git but not released | Use `fetchpatch` from upstream commit |
| Nix-specific issue (e.g., build system flags) | Patch in nixpkgs only |
| Architecture detection failure | Fix upstream, patch in nixpkgs until next release |
| Deep endianness bug | Submit upstream PR, carry `fetchpatch` until merged and released |

## PR Description Template

```markdown
## Description

Add s390x (IBM Z) support to <package>.

## Changes

- <specific change 1>
- <specific change 2>

## Testing

- Cross-compiled with `nix build .#pkgsCross.s390x.<package>` ✓
- Verified binary type: `ELF 64-bit MSB executable, IBM S/390` ✓
- Runtime tested under QEMU user-mode emulation ✓

## References

- linux-on-ibm-z port: https://github.com/linux-on-ibm-z/<repo>
- S390X Porting Guide: https://github.com/<org>/nix-on-z/blob/main/S390X-PORTING-GUIDE.md
```
