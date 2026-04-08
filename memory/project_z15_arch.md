---
name: z15 architecture targeting
description: LinuxONE Community Cloud is z15 (machine 8561); gcc.arch=z15 set globally; requires gccarch-z15 system feature in nix.conf
type: project
---

LinuxONE Community Cloud test machine is z15 (machine type 8561, 2 cores, 4GB RAM).
Set `gcc.arch = "z15"` in both `platforms.nix` (native) and `examples.nix` (cross).
Required `/etc/nix/nix.conf` on z: `system-features = benchmark big-parallel gccarch-z15 nixos-test uid-range`

**Why:** Setting `gcc.arch` makes nixpkgs add `gccarch-z15` as a required system feature on derivations. Without registering it in nix.conf, all builds fail with "missing system features".

**How to apply:** When changing `gcc.arch`, always update `/etc/nix/nix.conf` system-features on the target machine to match. The `nix run .#check-arch` script detects hardware but does not yet configure system-features.

TODO: Rebuild nix itself with z15 optimization after bootstrap completes (not blocking, but nix's hashing/SQLite would benefit from z15 SIMD).
