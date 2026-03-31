---
name: upstream acceptance strategy
description: User wants to fix real test issues alongside s390x patches to improve chances of upstream acceptance
type: project
---

The goal is to get s390x changes accepted upstream into NixOS/nix. The user wants to fix real test-related issues (not just s390x-specific ones) alongside the architecture patches, because upstream maintainers are more likely to accept a PR that improves test infrastructure for everyone.

**Why:** Pure architecture additions are harder to get merged. Bundling real bug fixes increases value to upstream.

**How to apply:** When investigating test failures, prioritize fixes that benefit all platforms (e.g., C API test sandbox issues, WorkerProto serialization bugs) and package them as separate patches alongside the s390x-specific ones.
