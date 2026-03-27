#!/usr/bin/env bash
set -euo pipefail

# Run Nix test suites and capture results.
# Run after 16-nix-build-tests.sh completes.

NIX_SRC="${HOME}/nix"
BUILD_DIR="${NIX_SRC}/build"
RESULTS_DIR="${HOME}/nix-test-results"

mkdir -p "$RESULTS_DIR"

cd "$NIX_SRC"

echo "=== Running Nix unit tests on s390x ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Machine: $(uname -m) $(uname -r)"
echo ""

# Unit tests (C++ GoogleTest)
echo "--- Unit tests ---"
for suite in nix-util-tests nix-store-tests nix-expr-tests nix-fetchers-tests nix-flake-tests; do
    echo ""
    echo "Running ${suite}..."
    if meson test -C "$BUILD_DIR" "$suite" --verbose 2>&1 | tee "${RESULTS_DIR}/${suite}.log"; then
        echo "PASS: ${suite}"
    else
        echo "FAIL: ${suite} (see ${RESULTS_DIR}/${suite}.log)"
    fi
done

# Functional tests (bash scripts, run the main suite)
echo ""
echo "--- Functional tests (main suite) ---"
if meson test -C "$BUILD_DIR" --suite main --verbose 2>&1 | tee "${RESULTS_DIR}/functional-main.log"; then
    echo "PASS: functional main suite"
else
    echo "SOME FAILURES in functional main suite (see ${RESULTS_DIR}/functional-main.log)"
fi

# Summary
echo ""
echo "=== Test results saved to ${RESULTS_DIR}/ ==="
echo ""
echo "Phase 17 complete: tests executed."
echo "Review logs in ${RESULTS_DIR}/ for details."
