# ModemManager — manages mobile broadband (3G/4G/5G) modems and SMS.
#
# WHY DISABLE: IBM Z has no modem hardware. There is no USB, no PCIe slots
# for cellular cards, no Bluetooth. ModemManager polls D-Bus for devices that
# will never appear, wasting CPU cycles and memory (~15MB RSS) for zero benefit.
#
# Ubuntu installs it by default because the same server image targets laptops
# and desktops where cellular modems exist.
{
  name = "disable-modemmanager";
  description = "ModemManager — no modem hardware exists on IBM Z";
  script = ''
    disable_service ModemManager.service
  '';
}
