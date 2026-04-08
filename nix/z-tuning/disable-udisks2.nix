# udisks2 — desktop storage management daemon (automount, eject, SMART).
#
# WHY DISABLE: udisks2 handles USB drives, SD cards, optical media, and
# desktop disk operations (format, eject, mount-on-insert). Z has none of
# these — storage is DASD or virtio-blk, managed by the hypervisor.
# udisks2 sits idle on D-Bus waiting for udev events from hardware that
# doesn't exist.
{
  name = "disable-udisks2";
  description = "udisks2 — no removable media or desktop storage on Z";
  script = ''
    disable_service udisks2.service
  '';
}
