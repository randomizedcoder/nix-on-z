# Testing Strategy

[Back to overview](../S390X-PORTING-GUIDE.md)

---

## Cross-Compilation (No s390x Hardware Needed)

Build packages using the nixpkgs cross-compilation infrastructure:

```bash
# Single package
nix build nixpkgs#pkgsCross.s390x.hello

# Build and check outputs
nix build nixpkgs#pkgsCross.s390x.coreutils
file result/bin/ls
# Expected: ELF 64-bit MSB executable, IBM S/390, version 1 (SYSV)
```

This tests that the package **compiles** for s390x, but does not verify runtime behavior.

## QEMU User-Mode Emulation

Run s390x binaries on x86_64 using QEMU user-mode:

```bash
# Install QEMU (on NixOS)
nix-env -iA nixpkgs.qemu

# Register binfmt handler
# (NixOS: boot.binfmt.emulatedSystems = [ "s390x-linux" ];)

# Run cross-compiled binary
qemu-s390x ./result/bin/hello
```

**Limitations:**
- Slow (~10-50x slower than native)
- Some syscalls not fully emulated
- Threading behavior may differ
- No hardware crypto/compression acceleration

## Native Hardware

For full verification, use real s390x hardware:

**IBM LinuxONE Community Cloud:**
- Free access to LinuxONE virtual servers
- Register at: https://linuxone.cloud.marist.edu/
- Ubuntu and SUSE images available
- Install Nix on the VM using the nix-on-z bootstrap

**IBM Z Development and Test Environment (ZD&T):**
- x86 emulation of z/Architecture
- Available through IBM PartnerWorld

## Test Result Tracking

Use this template for tracking package test results:

```markdown
| Package | Cross-Build | QEMU Run | Native Run | Notes |
|---------|-------------|----------|------------|-------|
| hello   | OK          | OK       | -          |       |
| coreutils | OK        | OK       | -          |       |
```

## Initial Cross-Compilation Test Matrix

All tests run via `nix build nixpkgs#pkgsCross.s390x.<pkg> --dry-run` (evaluation + build graph validation).

### Tier 1: Bootstrap Chain

| Package | Eval | Notes |
|---------|------|-------|
| hello | PASS | 1 derivation |
| coreutils | PASS | Already cached in binary cache |
| bash | PASS | 2 derivations (readline + bash-interactive) |

### Tier 2: Essential Build Dependencies

| Package | Eval | Notes |
|---------|------|-------|
| zlib | PASS | 1 derivation |
| openssl | PASS | Already cached in binary cache |
| curl | PASS | 5 derivations (zlib, nghttp2, zstd, libssh2, curl) |
| cmake | PASS | 9 derivations (libarchive, libuv, rhash, curl) |
| python3 | PASS | Large graph; Python 3.13.12 with libffi, gdbm, mpdecimal |
| perl | PASS | 2 derivations; uses perl-cross for cross-compilation |
| pkg-config | PASS | 6 derivations (pkg-config 0.29.2 + wrapper hooks) |
| pcre2 | PASS | Already cached in binary cache |
| protobuf | PASS | 4 derivations; protobuf v34.0 with abseil-cpp |
| sqlite | PASS | 2 derivations (zlib + sqlite 3.51.2) |

### Tier 3-4: Applications

| Package | Eval | Notes |
|---------|------|-------|
| go | PASS | Go 1.26.1; 7 derivations |
| nodejs | PASS | Node.js 24.14.0; builds ICU, simdutf, simdjson |
| nginx | PASS | Nginx 1.28.2; applies endianness/sizeof patches for cross |
| postgresql | PASS | Pulls in ICU, LLVM 21.1.8, readline, perl |
| mariadb | PASS | 98 derivations; 670 MiB fetch, ~2.7 GiB unpacked |
| redis | PASS | 90 derivations; full LLVM/clang, systemd stack |
| kubernetes | PASS | 4 derivations; kubectl + kubernetes 1.35.2 |
| containerd | PASS | 20 derivations; btrfs-progs, e2fsprogs, systemd |
| helm | PASS | 68 derivations; massive dependency tree |
| prometheus | PASS | 31 derivations; includes Node.js for asset pipeline |
| etcd | PASS | 9 derivations; etcdserver, etcdctl, etcdutl |
| nats-server | PASS | 3 derivations; clean Go build |
| caddy | PASS | 3 derivations; uses Go 1.25.8 |

### Failed Evaluations

| Package | Result | Reason | Fix |
|---------|--------|--------|-----|
| openjdk | FAIL | s390x not in `meta.platforms` | Add `"s390x-linux"` to platforms list |
| grafana | FAIL | s390x not in `meta.platforms` | Add `"s390x-linux"` to platforms list |
| terraform | FAIL | BSL unfree license | Not s390x-specific; needs `allowUnfree` |
| consul | FAIL | BSL unfree license | Not s390x-specific; needs `allowUnfree` |

**Key finding:** 26 of 30 tested packages (87%) evaluate successfully for s390x cross-compilation.
Several packages (openssl, coreutils, pcre2) already have s390x binaries in the NixOS binary cache,
confirming they have been successfully built before.
