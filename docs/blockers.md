# Packages Blocked on Big-Endian

[Back to overview](../S390X-PORTING-GUIDE.md)

---

## Confirmed Blockers

These packages explicitly mark big-endian platforms as unsupported via
`badPlatforms = lib.platforms.bigEndian`:

| Package | Expression | Blocker | Fixable? |
|---------|------------|---------|----------|
| `aws-c-common` | `badPlatforms = lib.platforms.bigEndian` | Endianness assumptions in byte manipulation | **Likely fixable** — Amazon has been adding BE support |
| `skia-pathops` | `badPlatforms = lib.platforms.bigEndian` | Path operations assume LE memory layout | **Hard** — deep in Skia rendering pipeline |
| `webrtc-audio-processing_1` | `badPlatforms = lib.platforms.bigEndian` | Audio codec byte order | **Medium** — codec-specific fixes needed |

**Scan complete** — only **3 packages** in all of nixpkgs use `badPlatforms = lib.platforms.bigEndian`.
This is a surprisingly small number, meaning most packages either work on big-endian or
simply haven't been tested (and don't explicitly block it).

## Analysis

**`aws-c-common`** — This is the foundational AWS C library. Blocking this cascades to block
all AWS SDK packages (`aws-sdk-cpp`, `aws-cli`, etc.). The IBM z/OS team has been working with
Amazon on BE support. Check recent upstream PRs before assuming this is still broken.

**`skia-pathops`** — Used by Flutter and some rendering pipelines. The endianness issues are
deep in the path geometry code. However, Chromium (which includes Skia) does have linux-on-ibm-z
patches, suggesting the broader Skia might work.

**`webrtc-audio-processing_1`** — Audio codecs often have endianness-sensitive PCM handling.
The linux-on-ibm-z `WebRTC` port may have relevant patches.

## Non-Blockers Referencing `bigEndian`

Additional `bigEndian` references that are **not blockers**:
- `hping` (`pkgs/by-name/hp/hping/package.nix:45`): Uses `bigEndian` for build-time platform detection (`__BIG_ENDIAN_BITFIELD`) — this is correct behavior, not a blocker
- `sasquatch` (`pkgs/by-name/sa/sasquatch/package.nix:11`): Optional `bigEndian ? false` parameter for squashfs variant — actually supports BE

## Implicit Platform Exclusions

Two important packages exclude s390x via `meta.platforms` rather than `badPlatforms`:

| Package | Expression | Impact |
|---------|------------|--------|
| `openjdk` | `meta.platforms` lists x86_64, aarch64, armv7l, armv6l, ppc64le, riscv64 — **no s390x** | Blocks all JVM packages (Kafka, Cassandra, Elasticsearch, Scala, etc.) |
| `grafana` | `meta.platforms` lists x86_64, aarch64 (linux+darwin), riscv64 — **no s390x** | Go backend works, but Node.js frontend build may be restricted |

**OpenJDK is the highest-impact fix** — adding s390x to its platform list would unblock the entire JVM ecosystem.

## Other Potential Blockers

Packages that may fail on s390x without explicitly marking it:

- Packages depending on `aws-c-common` (transitive `badPlatforms` — cascades to aws-sdk-cpp, aws-cli, etc.)
- Packages with x86 inline assembly (`asm("...")` with x86 instructions)
- Packages using NASM/YASM (x86-only assemblers)
- Rust crates with `cfg(target_arch = "x86_64")` without s390x alternative
- Packages checking `stdenv.hostPlatform.isx86_64` and disabling features elsewhere (e.g., arrow-cpp disables SIMD on non-x86)
