# Swap file for memory-constrained Z VMs.
# LLVM/Clang linking needs 7+ GB (libclang-cpp.so link step was OOM-killed
# with 4GB swap). 16GB swap + 16GB RAM = 32GB total — comfortable headroom
# for ClickHouse and simultaneous large builds.
# Swap on z is less painful than x86 thanks to channel-based I/O, hardware
# page management, and CMMA. See docs/technical-reference.md for details.
{
  name = "swap";
  description = "Create 16GB swap file for linking large binaries (LLVM/Clang)";
  script = ''
    echo "--- Configuring swap ---"
    SWAP_SIZE="16G"
    if swapon --show | grep -q /swapfile; then
      echo "  swap already active"
    elif [ -f /swapfile ]; then
      echo "  enabling existing /swapfile"
      swapon /swapfile
    else
      echo "  creating $SWAP_SIZE swap file..."
      fallocate -l "$SWAP_SIZE" /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      if ! grep -q /swapfile /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
      fi
      echo "  created and enabled $SWAP_SIZE swap"
    fi
  '';
}
