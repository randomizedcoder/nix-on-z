---
name: s390x character set challenges
description: s390x EBCDIC default character set expected to cause issues in nix, will need patches
type: project
---

s390x historically uses EBCDIC as its default character set. While Ubuntu on s390x runs in ASCII/UTF-8 mode, there may be architecture-specific character handling assumptions in C/C++ code that surface as bugs.

**Why:** Special handling and additional patches are very likely needed. Character-related issues are an important part of the effort to get nix working correctly on s390x.

**How to apply:** When debugging test failures or unexpected behavior on s390x, consider character encoding as a potential root cause. Watch for locale-dependent string operations, byte-order assumptions in text processing, and any code that makes ASCII assumptions about the platform.
