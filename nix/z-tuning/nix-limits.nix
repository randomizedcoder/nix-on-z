# Raise resource limits for nix build users (nixbld).
# Nix daemon runs builds as these users; default limits are too low
# for large builds that open thousands of files.
{
  name = "nix-limits";
  description = "Raise file/process limits for nix build users";
  script = ''
    echo "--- Configuring nix build user limits ---"
    cat > /etc/security/limits.d/99-nix-build.conf <<'LIMITS'
nixbld  soft  nofile  1048576
nixbld  hard  nofile  1048576
nixbld  soft  nproc   unlimited
nixbld  hard  nproc   unlimited
LIMITS
    echo "  applied /etc/security/limits.d/99-nix-build.conf"
  '';
}
