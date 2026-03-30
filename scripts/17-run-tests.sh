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

# Parse individual test counts from a meson test log.
# Meson prints a summary line like: "Ok:  1932  Expected Fail:  0  Fail:  0  ..."
parse_test_counts() {
    local logfile="$1"
    local ok skip fail
    ok=$(grep -oP 'Ok:\s+\K[0-9]+' "$logfile" | tail -n 1)
    skip=$(grep -oP 'Skipped:\s+\K[0-9]+' "$logfile" | tail -n 1)
    fail=$(grep -oP 'Fail:\s+\K[0-9]+' "$logfile" | tail -n 1)
    echo "${ok:-0} ${skip:-0} ${fail:-0}"
}

# Unit tests (C++ GoogleTest)
echo "--- Unit tests ---"
total_unit_ok=0
total_unit_fail=0
for suite in nix-util-tests nix-store-tests nix-expr-tests nix-fetchers-tests nix-flake-tests; do
    echo ""
    echo "Running ${suite}..."
    if meson test -C "$BUILD_DIR" "$suite" --verbose --timeout-multiplier "$TIMEOUT_MULT" 2>&1 | tee "${RESULTS_DIR}/${suite}.log"; then
        echo "PASS: ${suite}"
    else
        echo "FAIL: ${suite} (see ${RESULTS_DIR}/${suite}.log)"
    fi
    read -r ok skip fail < <(parse_test_counts "${RESULTS_DIR}/${suite}.log")
    total_unit_ok=$((total_unit_ok + ok))
    total_unit_fail=$((total_unit_fail + fail))
done

# Functional tests — all suites
echo ""
echo "--- Functional tests ---"
func_suites=(main flakes ca dyn-drv git git-hashing local-overlay-store plugins libstoreconsumer)
total_func_ok=0
total_func_skip=0
total_func_fail=0

for suite in "${func_suites[@]}"; do
    echo ""
    echo "Running functional suite: ${suite}..."
    if meson test -C "$BUILD_DIR" --suite "$suite" --verbose --timeout-multiplier "$TIMEOUT_MULT" --print-errorlogs 2>&1 | tee "${RESULTS_DIR}/functional-${suite}.log"; then
        echo "PASS: functional ${suite}"
    else
        echo "SOME FAILURES in functional ${suite} (see ${RESULTS_DIR}/functional-${suite}.log)"
    fi
    read -r ok skip fail < <(parse_test_counts "${RESULTS_DIR}/functional-${suite}.log")
    total_func_ok=$((total_func_ok + ok))
    total_func_skip=$((total_func_skip + skip))
    total_func_fail=$((total_func_fail + fail))
done

# Summary
echo ""
echo "=== Summary ==="
echo "Unit tests:       ${total_unit_ok} passed, ${total_unit_fail} failed"
echo "Functional tests: ${total_func_ok} passed, ${total_func_fail} failed, ${total_func_skip} skipped"
echo ""
echo "Logs saved to ${RESULTS_DIR}/"
echo ""
echo "Phase 17 complete: tests executed."
