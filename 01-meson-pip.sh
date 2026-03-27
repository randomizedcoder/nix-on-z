#!/usr/bin/env bash
set -euo pipefail

# Install meson >= 1.1 via pip (Ubuntu 22.04 ships 0.61).

pip3 install --user meson

MESON_BIN="${HOME}/.local/bin/meson"

if [[ -x "$MESON_BIN" ]]; then
    echo "meson installed: $("$MESON_BIN" --version)"
else
    echo "error: meson not found at $MESON_BIN" >&2
    exit 1
fi

echo "Phase 1 complete: meson installed via pip."
