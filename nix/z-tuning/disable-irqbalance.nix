# irqbalance — distributes hardware interrupts across CPUs.
#
# WHY DISABLE: On a 2-vCPU VM, irqbalance has almost nothing to balance.
# The kernel's default IRQ affinity is sufficient. irqbalance wakes up
# periodically (every 10s by default) to re-evaluate, adding unnecessary
# context switches.
#
# NOTE: On larger Z systems (8+ vCPUs, high I/O), keep irqbalance enabled.
# It becomes valuable when you have many I/O devices (DASDs, network
# adapters) competing for interrupt processing time.
{
  name = "disable-irqbalance";
  description = "irqbalance — negligible benefit on 2-vCPU VMs";
  script = ''
    disable_service irqbalance.service
  '';
}
