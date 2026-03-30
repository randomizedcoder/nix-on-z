#!/usr/bin/env bash
set -euo pipefail

# Run shellcheck on every .sh file in this repo.

if ! command -v shellcheck > /dev/null 2>&1; then
    echo "error: shellcheck not found" >&2
    echo "  install with: sudo apt install shellcheck" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pass=0
fail=0
failed_files=()

mapfile -t scripts < <(find "$SCRIPT_DIR" -maxdepth 1 -name '*.sh' -type f | sort)

for script in "${scripts[@]}"; do
    name="$(basename "$script")"
    if shellcheck -S warning "$script" > /dev/null 2>&1; then
        printf "  %-30s PASS\n" "$name"
        pass=$((pass + 1))
    else
        printf "  %-30s FAIL\n" "$name"
        shellcheck -S warning "$script" || true
        failed_files+=("$name")
        fail=$((fail + 1))
    fi
done

echo ""
echo "Results: ${pass} passed, ${fail} failed out of $(( pass + fail )) scripts"

if (( fail > 0 )); then
    echo ""
    echo "Failed scripts:"
    for f in "${failed_files[@]}"; do
        echo "  $f"
    done
    exit 1
fi

echo ""
echo "Phase 19 complete: all scripts pass shellcheck."
