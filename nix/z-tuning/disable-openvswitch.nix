# Open vSwitch (OVS) — software-defined networking virtual switch.
#
# WHY IT'S INSTALLED: Ubuntu on Z includes OVS because mainframes commonly
# run many VMs with complex virtual networking (z/VM guest LANs, VSWITCH).
# OVS provides programmable L2/L3 switching with OpenFlow support — useful
# for cloud infrastructure and SDN deployments on Z.
#
# WHY DISABLE: On a single-purpose build VM (like LinuxONE Community Cloud),
# we have one network interface with simple connectivity. OVS runs two
# daemons (ovsdb-server + ovs-vswitchd) that mlockall their memory,
# consuming resources for networking we don't use. If you later need virtual
# networking for multi-VM test environments, re-enable this.
{
  name = "disable-openvswitch";
  description = "Open vSwitch — not needed on single-purpose build VMs";
  script = ''
    disable_service ovsdb-server.service
    disable_service ovs-vswitchd.service
  '';
}
