---
name: rsync exclude pattern anchoring
description: rsync --exclude patterns must use leading / to anchor to root, otherwise they match at any depth
type: feedback
---

Rsync `--exclude='build/'` matches directories named `build/` at ANY level in the tree, including source directories like `src/libstore/build/`. Must use `--exclude='/build/'` to anchor to the sync root.

**Why:** This caused a multi-hour debugging session where the nix source was partially synced to the remote s390x machine, missing critical source files in `src/libstore/build/` and `src/libstore/unix/build/`.

**How to apply:** Always anchor rsync exclude patterns with leading `/` when the intent is to exclude a top-level directory. Review exclude lists carefully when syncing source trees that may have subdirectories with common names like `build/`, `test/`, `lib/`.
