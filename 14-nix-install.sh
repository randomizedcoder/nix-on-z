#!/usr/bin/env bash
set -euo pipefail

# Install Nix and set up /nix/store.
# Run as the build user (not root) — uses sudo internally where needed.
# Meson is installed via pip in ~/.local/bin and needs PYTHONPATH preserved.

NIX_SRC="${HOME}/nix"
BUILD_DIR="${NIX_SRC}/build"
MESON_BIN="${HOME}/.local/bin/meson"
PYTHON_SITE="$(python3 -c 'import site; print(site.getusersitepackages())')"

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "error: build directory not found at ${BUILD_DIR}" >&2
    echo "  run 13-nix-build.sh first" >&2
    exit 1
fi

echo "Installing Nix..."
sudo env \
    PATH="${HOME}/.local/bin:${PATH}" \
    PYTHONPATH="${PYTHON_SITE}" \
    meson install -C "$BUILD_DIR"

# Libraries install to /usr/local/lib/s390x-linux-gnu on s390x
# GCC 14's libstdc++ is in /usr/local/lib64 — must be in ldconfig
# so the nix binary can find it without LD_LIBRARY_PATH
echo "/usr/local/lib64" | sudo tee /etc/ld.so.conf.d/gcc14.conf > /dev/null
echo "/usr/local/lib/s390x-linux-gnu" | sudo tee /etc/ld.so.conf.d/nix.conf > /dev/null
sudo ldconfig

echo "Creating /nix/store..."
sudo mkdir -p /nix/store
sudo chmod 1775 /nix/store

echo "Creating nixbld group and users..."
if ! getent group nixbld > /dev/null 2>&1; then
    sudo groupadd -r nixbld
fi

for i in $(seq 1 10); do
    USERNAME="nixbld${i}"
    if ! id "$USERNAME" > /dev/null 2>&1; then
        sudo useradd -r -g nixbld -G nixbld \
            -d /var/empty -s /usr/sbin/nologin \
            -c "Nix build user ${i}" \
            "$USERNAME"
    fi
done

echo "Setting /nix/store ownership..."
sudo chown root:nixbld /nix/store

echo "Phase 14 complete: Nix installed."
echo "Test with: nix --version"
