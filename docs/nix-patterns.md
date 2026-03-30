# Nix Expression Patterns for s390x

[Back to overview](../S390X-PORTING-GUIDE.md)

---

Copy-paste recipes for common s390x porting situations, drawn from real nixpkgs code.

## Platform Predicate Check

Use `isS390x` to conditionally change behavior for s390x:

```nix
# Source: lib/systems/inspect.nix:232-242
stdenv.hostPlatform.isS390x  # true only for s390x (64-bit)
stdenv.hostPlatform.isS390   # true for both s390 and s390x
```

## Big-Endian Check

For issues that affect all big-endian platforms (s390x, powerpc, etc.), use:

```nix
stdenv.hostPlatform.isBigEndian
```

This is preferred when the issue isn't s390x-specific but is an endianness problem.

## Disable a Feature on s390x

Pattern from `pcre2/default.nix:26` — conditionally disable JIT:

```nix
configureFlags = [
  "--enable-jit=${if stdenv.hostPlatform.isS390x then "no" else "auto"}"
];
```

For meson-based builds:
```nix
mesonFlags = lib.optionals stdenv.hostPlatform.isS390x [
  "-Djit=disabled"
];
```

## Set Architecture-Specific Target

Pattern from `openblas/make.nix:142` — set the s390x-specific target:

```nix
makeFlags = [
  "TARGET=${if stdenv.hostPlatform.isS390x then "ZARCH_GENERIC" else ...}"
];
```

Another example — Rust target:
```nix
CARGO_BUILD_TARGET = if stdenv.hostPlatform.isS390x
  then "s390x-unknown-linux-gnu"
  else ...;
```

## Exclude Package via `badPlatforms`

When a package fundamentally cannot work on big-endian (or s390x specifically):

```nix
# Source: aws-c-common/package.nix:61
meta = {
  badPlatforms = lib.platforms.bigEndian;
};
```

For s390x-only exclusion (not all BE platforms):
```nix
meta = {
  badPlatforms = [ "s390x-linux" ];
};
```

## Add s390x to a Platform List

When a package excludes big-endian but s390x actually works (e.g., Node.js has IBM's V8 port):

```nix
# Pattern from nodejs/nodejs.nix
meta.platforms = lib.platforms.linux ++ lib.platforms.darwin;
# Or explicitly add:
meta.platforms = with lib.platforms; linux;  # includes s390x-linux
```

If a package uses `lib.platforms.littleEndian` and you've confirmed s390x works, add it:
```nix
meta.platforms = lib.platforms.littleEndian ++ [ "s390x-linux" ];
```

## Fetch Bootstrap Binary with s390x Hash

Pattern from `pkgs/stdenv/linux/bootstrap-files/s390x-unknown-linux-gnu.nix`:

```nix
fetchurl {
  url = "http://hydra.nixos.org/build/268609502/download/1/on-server/${name}";
  sha256 = "<hash for s390x binary>";
};
```

## Apply an s390x-Specific Patch

Fetch a patch from linux-on-ibm-z or another source, conditionally:

```nix
patches = lib.optionals stdenv.hostPlatform.isS390x [
  (fetchpatch {
    name = "s390x-support.patch";
    url = "https://github.com/linux-on-ibm-z/<repo>/commit/<sha>.patch";
    hash = "sha256-...";
  })
];
```

## Cross-Compilation Conditional

For code that needs to differentiate between native and cross-compiled s390x builds:

```nix
# Are we cross-compiling?
stdenv.hostPlatform != stdenv.buildPlatform

# Cross-compile to s390x from x86_64:
# nix build .#pkgsCross.s390x.<package>
```

## Conditional Dependencies

Add s390x-specific build dependencies:

```nix
buildInputs = [
  # ... common deps ...
] ++ lib.optionals stdenv.hostPlatform.isS390x [
  # s390x might need specific libraries
];

nativeBuildInputs = [
  # ... common native deps ...
] ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
  # cross-compilation tools
];
```
