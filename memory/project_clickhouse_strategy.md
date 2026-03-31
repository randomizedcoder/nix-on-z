---
name: ClickHouse s390x build strategy
description: ClickHouse s390x — pivoted to native-first after 11 cross-compilation iterations hit sub-cmake compiler issues
type: project
---

ClickHouse s390x cross-compilation ran through 11 build iterations. Builds 1-8 fixed objcopy, compiler-rt, ISAL, HDFS, toolchain file issues. Builds 9-11 fixed the sub-cmake `execute_process` (objcopy symlinks work, ccache disabled) but the sub-cmake still needs the right build-platform compiler (`buildPackages.llvmPackages_21.clang-unwrapped`).

**Why:** The fundamental problem is ClickHouse's `execute_process` sub-cmake for native tools (protoc) doesn't compose with Nix's cross-compilation wrappers. On native s390x, all of these issues disappear because `buildPlatform == hostPlatform`.

**How to apply:** Build natively on s390x first — only needs the s390x cmake flags (SIMD disable, OpenSSL, ISAL/HDFS off) and ICU BE fix, all already in generic.nix. Then return to cross-compilation with a known-good baseline. See docs/clickhouse-challenges.md for the complete analysis.
