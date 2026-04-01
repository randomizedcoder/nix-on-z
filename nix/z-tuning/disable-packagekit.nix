# PackageKit — D-Bus abstraction layer for GUI package management tools.
#
# WHY DISABLE: PackageKit exists so that GNOME Software, KDE Discover, and
# other GUI tools can install packages. There is no GUI on Z — we access it
# only via SSH. PackageKit sits idle consuming ~20MB RSS, listening on D-Bus
# for requests that never come.
{
  name = "disable-packagekit";
  description = "PackageKit — no GUI on Z, D-Bus package daemon is idle";
  script = ''
    disable_service packagekit.service
  '';
}
