#!/usr/bin/env bash

# Verify the Nix build and test environment on the target machine.
# Run after building Nix (13-nix-build.sh) but before running tests.
# This script probes every prerequisite the test suite needs and reports
# what will pass, fail, or skip — before you spend 20 minutes finding out.

NIX_SRC="${HOME}/nix"
BUILD_DIR="${NIX_SRC}/build"

PASS=0
WARN=0
FAIL=0
INFO=0

pass() { PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m  %s\n" "$*"; }
warn() { WARN=$((WARN + 1)); printf "  \033[33mWARN\033[0m  %s\n" "$*"; }
fail() { FAIL=$((FAIL + 1)); printf "  \033[31mFAIL\033[0m  %s\n" "$*"; }
info() { INFO=$((INFO + 1)); printf "  \033[36mINFO\033[0m  %s\n" "$*"; }

divider() { printf "\n=== %s ===\n" "$1"; }

# ---------------------------------------------------------------------------
divider "System"
# ---------------------------------------------------------------------------

info "Architecture: $(uname -m)"
info "Kernel: $(uname -r)"
info "OS: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s)"

if [[ "$(uname -m)" == "s390x" ]]; then
    pass "Running on s390x"
else
    info "Not s390x — that's fine, this script works on any arch"
fi

# ---------------------------------------------------------------------------
divider "Nix Build"
# ---------------------------------------------------------------------------

if [[ -d "$BUILD_DIR" ]]; then
    pass "Build directory exists: $BUILD_DIR"
else
    fail "Build directory not found: $BUILD_DIR"
    echo "       Run meson setup + meson compile first."
fi

nix_bin="$BUILD_DIR/src/nix/nix"
if [[ -x "$nix_bin" ]]; then
    nix_version=$("$nix_bin" --version 2>/dev/null || echo "unknown")
    pass "Nix binary built: $nix_version"
else
    fail "Nix binary not found at $nix_bin"
fi

installed_nix=$(command -v nix 2>/dev/null || true)
if [[ -n "$installed_nix" ]]; then
    installed_version=$(nix --version 2>/dev/null || echo "unknown")
    info "Installed nix: $installed_nix ($installed_version)"
else
    warn "No nix on PATH — some tests need an installed nix"
fi

# ---------------------------------------------------------------------------
divider "Sandbox Shell"
# ---------------------------------------------------------------------------

# The sandbox shell is a static binary that Nix bind-mounts as /bin/sh
# inside the build sandbox. Without it, sandboxed builds can't run.

sandbox_shell=""
config_hdr="$BUILD_DIR/src/libstore/store-config-private.hh"
if [[ -f "$config_hdr" ]]; then
    sandbox_shell=$(grep '^#define SANDBOX_SHELL ' "$config_hdr" \
        | sed 's/.*"\(.*\)".*/\1/' 2>/dev/null || true)
fi

if [[ -n "$sandbox_shell" && "$sandbox_shell" != "__embedded_sandbox_shell__" ]]; then
    pass "Sandbox shell configured: $sandbox_shell"
    if [[ -x "$sandbox_shell" ]]; then
        pass "Sandbox shell binary exists and is executable"
    else
        fail "Sandbox shell binary not found: $sandbox_shell"
    fi
    if file "$sandbox_shell" 2>/dev/null | grep -q "statically linked"; then
        pass "Sandbox shell is statically linked"
    else
        warn "Sandbox shell is dynamically linked — may not work inside empty chroot"
    fi
    if "$sandbox_shell" -c 'echo ok' >/dev/null 2>&1; then
        pass "Sandbox shell executes successfully"
    else
        fail "Sandbox shell won't execute"
    fi
else
    fail "No sandbox shell configured (SANDBOX_SHELL not set in build)"
    echo "       Sandboxed builds will fail. Install bash-static and reconfigure:"
    echo "       meson setup build --reconfigure -Dlibstore:sandbox-shell=/usr/bin/bash-static"
fi

# Check for common sandbox shell candidates
for candidate in /usr/bin/bash-static /usr/bin/busybox; do
    if [[ -x "$candidate" ]]; then
        linkage=$(file "$candidate" | grep -o 'statically linked' || echo 'dynamic')
        info "Available static shell: $candidate ($linkage)"
    fi
done

# busybox warning
if command -v busybox >/dev/null 2>&1; then
    warn "busybox is on PATH — meson will detect it for functional tests"
    echo "       This causes 19+ functional tests to run (instead of skip) and fail"
    echo "       because Ubuntu's busybox can't handle the test scripts."
    echo "       Consider: sudo apt-get remove busybox-static"
fi

# ---------------------------------------------------------------------------
divider "Functional Test Variables"
# ---------------------------------------------------------------------------

subst_vars="$BUILD_DIR/src/nix-functional-tests/common/subst-vars.sh"
if [[ -f "$subst_vars" ]]; then
    pass "Generated subst-vars.sh exists"

    # Source it to check variables (unset first to avoid leaking caller env)
    unset bash bindir system version shell busybox 2>/dev/null || true
    # shellcheck disable=SC1090
    source "$subst_vars"

    [[ -n "${bash:-}" ]]    && pass "\$bash = $bash"       || fail "\$bash is not set"
    [[ -n "${bindir:-}" ]]  && pass "\$bindir = $bindir"   || fail "\$bindir is not set"
    [[ -n "${system:-}" ]]  && pass "\$system = $system"   || fail "\$system is not set"
    [[ -n "${version:-}" ]] && pass "\$version = $version" || fail "\$version is not set"

    if [[ -n "${shell:-}" ]]; then
        pass "\$shell = $shell"
    else
        fail "\$shell is not set — formatter.sh and nix-profile.sh will fail"
        echo "       Fix: add 'shell=@bash@' to tests/functional/common/subst-vars.sh.in"
    fi

    if [[ -z "${busybox:-}" ]]; then
        pass "\$busybox is empty — busybox-dependent tests will skip (good)"
    else
        warn "\$busybox = $busybox — busybox-dependent tests will run"
    fi
else
    fail "subst-vars.sh not generated — run meson setup first"
fi

# ---------------------------------------------------------------------------
divider "User Namespaces (Sandbox Support)"
# ---------------------------------------------------------------------------

if [[ "$(uname)" == "Linux" ]]; then
    if [[ -L /proc/self/ns/user ]]; then
        pass "User namespace support detected (/proc/self/ns/user exists)"
    else
        warn "No /proc/self/ns/user — sandbox tests will skip"
    fi

    if unshare --user true 2>/dev/null; then
        pass "unshare --user works — sandboxed tests can run"
    else
        warn "unshare --user failed — sandboxed tests will skip"
    fi

    if [[ -f /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]]; then
        val=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)
        if [[ "$val" == "0" ]]; then
            pass "AppArmor unprivileged user namespaces: allowed"
        else
            warn "AppArmor restricts unprivileged user namespaces — some tests will skip"
        fi
    fi
fi

# ---------------------------------------------------------------------------
divider "Git"
# ---------------------------------------------------------------------------

if command -v git >/dev/null 2>&1; then
    git_version=$(git --version)
    pass "git installed: $git_version"

    # Check if file:// transport is restricted (CVE-2022-39253 backport)
    tmpdir=$(mktemp -d)

    git init -q "$tmpdir/a" 2>/dev/null
    git -C "$tmpdir/a" config user.email "test@test.com"
    git -C "$tmpdir/a" config user.name "Test"
    git -C "$tmpdir/a" commit --allow-empty -m init -q 2>/dev/null

    if git clone -q "file://$tmpdir/a" "$tmpdir/b" 2>/dev/null; then
        pass "git file:// transport works by default"
    else
        warn "git file:// transport is restricted (CVE-2022-39253 backport)"
        echo "       fetchGitSubmodules test may fail on recursive submodule clones"

        # Test if GIT_CONFIG_COUNT workaround helps
        if GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
           git clone -q "file://$tmpdir/a" "$tmpdir/c" 2>/dev/null; then
            pass "GIT_CONFIG_COUNT workaround works for direct clones"
        else
            fail "GIT_CONFIG_COUNT workaround does not work"
        fi

        # Test recursive submodule propagation
        git init -q "$tmpdir/d" 2>/dev/null
        git -C "$tmpdir/d" config user.email "test@test.com"
        git -C "$tmpdir/d" config user.name "Test"
        git -C "$tmpdir/d" commit --allow-empty -m init -q 2>/dev/null

        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
          git -C "$tmpdir/a" submodule add "$tmpdir/d" sub 2>/dev/null || true
        git -C "$tmpdir/a" commit -m sub -q 2>/dev/null || true

        if GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
           git clone -q --recurse-submodules "file://$tmpdir/a" "$tmpdir/e" 2>/dev/null; then
            pass "GIT_CONFIG_COUNT propagates to recursive submodule clones"
        else
            warn "GIT_CONFIG_COUNT does NOT propagate to recursive submodule clones"
            echo "       fetchGitSubmodules nested test will fail"
            echo "       This is a git version issue ($git_version)"
        fi
    fi
    rm -rf "$tmpdir"
else
    fail "git not installed — many tests will skip or fail"
fi

# ---------------------------------------------------------------------------
divider "/nix/store"
# ---------------------------------------------------------------------------

if [[ -d /nix/store ]]; then
    count=$(ls /nix/store 2>/dev/null | wc -l)
    if [[ "$count" -gt 10 ]]; then
        pass "/nix/store exists with $count entries"
    elif [[ "$count" -gt 0 ]]; then
        warn "/nix/store exists but has only $count entries — nested-sandboxing may fail"
    else
        warn "/nix/store exists but is empty — nested-sandboxing will fail"
    fi
else
    info "/nix/store does not exist — nested-sandboxing test will skip (good)"
fi

# ---------------------------------------------------------------------------
divider "External Tools"
# ---------------------------------------------------------------------------

for tool in jq sqlite3 dot hg ssh-keygen; do
    if command -v "$tool" >/dev/null 2>&1; then
        ver=$("$tool" --version 2>/dev/null | head -1 || echo "")
        pass "$tool: found${ver:+ ($ver)}"
    else
        info "$tool: not found (some tests may skip)"
    fi
done

# ---------------------------------------------------------------------------
divider "Shared Libraries"
# ---------------------------------------------------------------------------

if [[ -x "$nix_bin" ]]; then
    missing=$(ldd "$nix_bin" 2>/dev/null | grep "not found" || true)
    if [[ -z "$missing" ]]; then
        pass "All shared libraries for nix binary resolved"
    else
        fail "Missing shared libraries:"
        echo "$missing" | sed 's/^/       /'
    fi
fi

# ---------------------------------------------------------------------------
divider "Unit Test Binaries"
# ---------------------------------------------------------------------------

for suite in nix-util-tests nix-store-tests nix-expr-tests nix-fetchers-tests nix-flake-tests; do
    found=""
    for b in "$BUILD_DIR/src/$suite/$suite" "$BUILD_DIR/src/lib${suite#nix-}/$suite"; do
        if [[ -x "$b" ]]; then found="$b"; break; fi
    done
    if [[ -n "$found" ]]; then
        missing=$(ldd "$found" 2>/dev/null | grep "not found" || true)
        if [[ -z "$missing" ]]; then
            pass "$suite: binary OK"
        else
            fail "$suite: missing libs"
        fi
    else
        warn "$suite: binary not found"
    fi
done

# ---------------------------------------------------------------------------
divider "Known Failure Predictions"
# ---------------------------------------------------------------------------

echo ""
echo "Based on the checks above, predicting functional test outcomes:"
echo ""

# formatter.sh / nix-profile.sh
if [[ -n "${shell:-}" ]]; then
    pass "formatter.sh — \$shell is defined"
    pass "nix-profile.sh — \$shell is defined"
else
    fail "formatter.sh — will fail: \$shell unbound variable"
    fail "nix-profile.sh — will fail: \$shell unbound variable"
fi

# structured-attrs.sh
if nix --extra-experimental-features "nix-command flakes" registry list 2>/dev/null | grep -q nixpkgs; then
    pass "structured-attrs.sh — nixpkgs in flake registry"
else
    warn "structured-attrs.sh — will fail: 'nix develop' needs flake:nixpkgs (TODO_NixOS upstream)"
fi

# fetchGitSubmodules.sh — already checked above in Git section

# nested-sandboxing.sh
if [[ -d /nix/store ]]; then
    nix_bin_in_store=$(find /nix/store -name nix -type f -executable 2>/dev/null | head -1)
    if [[ -n "$nix_bin_in_store" ]]; then
        pass "nested-sandboxing.sh — nix binary found in /nix/store"
    else
        warn "nested-sandboxing.sh — will fail: needs nix deps in /nix/store"
    fi
else
    pass "nested-sandboxing.sh — /nix/store absent, test will skip"
fi

# ---------------------------------------------------------------------------
divider "Summary"
# ---------------------------------------------------------------------------

echo ""
printf "  \033[32m%d PASS\033[0m  " "$PASS"
printf "\033[33m%d WARN\033[0m  " "$WARN"
printf "\033[31m%d FAIL\033[0m  " "$FAIL"
printf "\033[36m%d INFO\033[0m\n" "$INFO"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
    echo "There are $FAIL issues that will cause test failures."
    echo "Fix them before running the test suite."
    exit 1
else
    echo "Environment looks good. Run tests with:"
    echo "  meson test -C build -t 10                    # all tests"
    echo "  meson test -C build --suite main -t 10       # functional tests only"
    exit 0
fi
