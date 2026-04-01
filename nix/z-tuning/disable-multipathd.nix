# multipathd — device-mapper multipath I/O management.
#
# WHY IT'S INSTALLED: Z systems often use FCP (Fibre Channel Protocol) or
# FICON-attached SAN storage with multiple physical paths for redundancy.
# multipathd manages failover between paths and load-balances I/O.
#
# WHY DISABLE: LinuxONE Community Cloud VMs use single-path virtio-blk
# storage — there are no multiple paths to manage. multipathd polls for
# path changes that can't happen, wasting CPU. If you're on a production
# Z system with FCP SAN, keep this enabled.
{
  name = "disable-multipathd";
  description = "multipathd — Community Cloud uses single-path virtio storage";
  script = ''
    disable_service multipathd.service
  '';
}
