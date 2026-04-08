# networkd-dispatcher — Python daemon that runs scripts on network state changes.
#
# WHY DISABLE: This daemon (~30MB RSS) runs permanently, waiting for
# systemd-networkd to report interface up/down events. On Z, the network
# configuration is static — the interface comes up at boot and stays up.
# There are no WiFi roaming events, no cable plug/unplug, no VPN toggling.
# The daemon idles consuming memory for events that never fire.
{
  name = "disable-networkd-dispatcher";
  description = "networkd-dispatcher — network is static on Z, no events to dispatch";
  script = ''
    disable_service networkd-dispatcher.service
  '';
}
