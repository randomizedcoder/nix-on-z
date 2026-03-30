# Debugging Commands

[Back to overview](../S390X-PORTING-GUIDE.md)

---

## Identifying Binary Architecture

```bash
# Check if a binary is s390x
file ./result/bin/hello
# ELF 64-bit MSB executable, IBM S/390, version 1 (SYSV), dynamically linked,
# interpreter /nix/store/...-glibc-.../lib/ld64.so.1, ...

# Check ELF details
readelf -h ./result/bin/hello | grep -E 'Class|Data|Machine'
#   Class:                             ELF64
#   Data:                              2's complement, big endian
#   Machine:                           IBM S/390
```

## Cross-Compilation Debugging

```bash
# Build with verbose output
nix build nixpkgs#pkgsCross.s390x.hello --print-build-logs

# Enter a cross-compilation shell
nix develop nixpkgs#pkgsCross.s390x.hello

# Check the cross compiler
s390x-unknown-linux-gnu-gcc --version

# Test a simple compile
echo 'int main() { return 0; }' | s390x-unknown-linux-gnu-gcc -x c - -o test
file test
# ELF 64-bit MSB executable, IBM S/390
```

## QEMU Debugging

```bash
# Run with strace
qemu-s390x -strace ./result/bin/hello

# Run with GDB
qemu-s390x -g 1234 ./result/bin/hello &
gdb-multiarch -ex "target remote :1234" ./result/bin/hello

# Check supported QEMU CPU features
qemu-s390x -cpu help
```

## Nixpkgs s390x Queries

```bash
# List all packages with s390x-specific code
grep -r "isS390x\|isS390\|s390" pkgs/ --include="*.nix" -l

# Find all bigEndian exclusions
grep -r "bigEndian" pkgs/ --include="*.nix" -l

# Check if a package is in the cross-compilation CI set
grep -A 50 "s390x" pkgs/top-level/release-cross.nix

# List bootstrap files
ls pkgs/stdenv/linux/bootstrap-files/s390x*
```

## Dependency Graph Analysis

These queries use the nix store database to analyze s390x build graph impact.
Requires `sqlite3` (use `nix-shell -p sqlite` if not available).

```bash
SQLITE=$(which sqlite3 || nix-shell -p sqlite --run "which sqlite3")
NIXDB=/nix/var/nix/db/db.sqlite

# Database overview
$SQLITE $NIXDB "SELECT count(*) || ' paths' FROM ValidPaths;
                SELECT count(*) || ' dependency edges' FROM Refs;
                SELECT count(*) || ' s390x paths' FROM ValidPaths WHERE path LIKE '%s390x%';"

# Top s390x target packages by DIRECT dependent count
$SQLITE $NIXDB "
SELECT replace(replace(v.path, '/nix/store/', ''), '.drv', '') as pkg,
       count(r.referrer) as direct_dependents
FROM ValidPaths v
JOIN Refs r ON r.reference = v.id
WHERE v.path LIKE '%s390x%.drv'
GROUP BY v.id
ORDER BY direct_dependents DESC
LIMIT 30;"

# Native build tools most used by s390x builds
$SQLITE $NIXDB "
SELECT replace(replace(v.path, '/nix/store/', ''), '.drv', '') as native_tool,
       count(DISTINCT r.referrer) as s390x_users
FROM ValidPaths v
JOIN Refs r ON r.reference = v.id
JOIN ValidPaths rv ON r.referrer = rv.id
WHERE rv.path LIKE '%s390x%.drv'
AND v.path LIKE '%.drv'
AND v.path NOT LIKE '%s390x%'
GROUP BY v.id
ORDER BY s390x_users DESC
LIMIT 30;"

# TRANSITIVE impact (slower — shells out to nix-store for each drv)
$SQLITE $NIXDB "SELECT path FROM ValidPaths WHERE path LIKE '%s390x%.drv'" \
  | while read drv; do
      name=$(echo "$drv" | sed 's|/nix/store/[a-z0-9]*-||; s|\.drv||')
      refs=$(nix-store -q --referrers-closure "$drv" 2>/dev/null | wc -l)
      echo "$refs|$name"
    done | sort -rn | head -40

# Full tree visualization of s390x stdenv
S390X_STDENV=$(nix eval --raw nixpkgs#pkgsCross.s390x.stdenv.drvPath)
nix-store -q --tree "$S390X_STDENV" | head -100
```

## Endianness Testing

```c
/* Quick endianness test program */
#include <stdio.h>
#include <stdint.h>

int main() {
    uint32_t val = 0x01020304;
    uint8_t *bytes = (uint8_t *)&val;
    printf("Byte order: %02x %02x %02x %02x\n",
           bytes[0], bytes[1], bytes[2], bytes[3]);
    /* Big-endian (s390x): 01 02 03 04 */
    /* Little-endian (x86): 04 03 02 01 */
    return 0;
}
```
