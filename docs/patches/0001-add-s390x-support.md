[< Patches overview](../patches.md) | [< README](../../README.md)

# Patch 1: s390x architecture support

## Stack pointer detection

**File:** `src/libmain/unix/stack.cc`

Adds s390x stack pointer register (R15 = `gregs[15]`) for the SIGSEGV stack overflow detector:

```cpp
#elif defined(__s390x__)
    sp = (char *) ((ucontext_t *) ctx)->uc_mcontext.gregs[15];
```

## Seccomp architecture

**File:** `src/libstore/unix/build/linux-derivation-builder.cc`

Adds the 31-bit s390 compat architecture for the seccomp sandbox filter,
following the existing pattern for aarch64/ARM and x86_64/x86:

```cpp
if (nativeSystem == "s390x-linux" && seccomp_arch_add(ctx, SCMP_ARCH_S390) != 0)
    printError("unable to add s390 seccomp architecture");
```
