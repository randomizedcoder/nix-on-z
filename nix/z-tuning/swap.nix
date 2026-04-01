# Swap file for memory-constrained Z VMs.
# ClickHouse linking can use 6-8GB; with 4GB RAM, swap is essential.
# 4GB swap + 4GB RAM = 8GB total — enough for lld to link ClickHouse.
{
  name = "swap";
  description = "Create 4GB swap file for linking large binaries";
  script = ''
    echo "--- Configuring swap ---"
    SWAP_SIZE="4G"
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
