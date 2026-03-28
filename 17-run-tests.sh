#!/usr/bin/env bash
set -euo pipefail

# Run all Nix test suites and capture results.
# Run after 16-nix-build-tests.sh completes.
#
# Prerequisites:
#   - jq >= 1.7 (built in 15-test-deps.sh)
#   - bash-static (installed in 00-apt-deps.sh, used as sandbox shell)
#   - 18-verify-test-env.sh passed (optional but recommended)

NIX_SRC="${HOME}/nix"
BUILD_DIR="${NIX_SRC}/build"
RESULTS_DIR="${HOME}/nix-test-results"
TIMEOUT_MULT=10

mkdir -p "$RESULTS_DIR"

cd "$NIX_SRC"

echo "=== Running Nix tests on s390x ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Machine: $(uname -m) $(uname -r)"
echo "jq: $(jq --version 2>/dev/null || echo 'not found')"
echo "sandbox shell: $(file /usr/bin/bash-static 2>/dev/null || echo 'not found')"
echo ""

# Unit tests (C++ GoogleTest)
echo "--- Unit tests ---"
unit_pass=0
unit_fail=0
for suite in nix-util-tests nix-store-tests nix-expr-tests nix-fetchers-tests nix-flake-tests; do
    echo ""
    echo "Running ${suite}..."
    if meson test -C "$BUILD_DIR" "$suite" --verbose --timeout-multiplier "$TIMEOUT_MULT" 2>&1 | tee "${RESULTS_DIR}/${suite}.log"; then
        echo "PASS: ${suite}"
        unit_pass=$((unit_pass + 1))
    else
        echo "FAIL: ${suite} (see ${RESULTS_DIR}/${suite}.log)"
        unit_fail=$((unit_fail + 1))
    fi
done

# Functional tests — all suites
echo ""
echo "--- Functional tests ---"
func_suites=(main flakes ca dyn-drv git git-hashing local-overlay-store plugins libstoreconsumer)

for suite in "${func_suites[@]}"; do
    echo ""
    echo "Running functional suite: ${suite}..."
    if meson test -C "$BUILD_DIR" --suite "$suite" --verbose --timeout-multiplier "$TIMEOUT_MULT" --print-errorlogs 2>&1 | tee "${RESULTS_DIR}/functional-${suite}.log"; then
        echo "PASS: functional ${suite}"
    else
        echo "SOME FAILURES in functional ${suite} (see ${RESULTS_DIR}/functional-${suite}.log)"
    fi
done

# Summary
echo ""
echo "=== Summary ==="
echo "Unit tests: ${unit_pass} passed, ${unit_fail} failed (out of 5 suites)"
echo "Functional test logs saved to ${RESULTS_DIR}/functional-*.log"
echo ""
echo "To see per-test results:"
echo "  grep -E '(OK|FAIL|SKIP)' ${RESULTS_DIR}/functional-main.log"
echo ""
echo "Phase 17 complete: tests executed."
