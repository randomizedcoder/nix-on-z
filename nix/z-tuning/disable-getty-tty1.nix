# getty@tty1 — virtual console login prompt on tty1.
#
# WHY DISABLE: Z has no physical display or keyboard — there is no tty1.
# Access is via SSH or the Z-specific serial consoles (hvc0, ttysclp0),
# which have their own getty services. This getty process sits waiting
# for input on a device that doesn't exist.
{
  name = "disable-getty-tty1";
  description = "getty@tty1 — no physical display on Z";
  script = ''
    disable_service getty@tty1.service
  '';
}
