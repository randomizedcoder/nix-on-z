# Pinned dependency versions for s390x bootstrap scripts.
# Single source of truth — every build script interpolates from here.
{
  gcc = {
    version = "14.2.0";
    url = "https://ftp.gnu.org/gnu/gcc/gcc-14.2.0/gcc-14.2.0.tar.xz";
  };

  boost = {
    version = "1.87.0";
    underscore = "1_87_0";
    url = "https://archives.boost.io/release/1.87.0/source/boost_1_87_0.tar.bz2";
  };

  nlohmann-json = {
    version = "3.11.3";
    url = "https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz";
  };

  toml11 = {
    version = "4.4.0";
    url = "https://github.com/ToruNiina/toml11.git";
  };

  sqlite = {
    version = "3490100";
    display = "3.49.1";
    year = "2025";
    url = "https://www.sqlite.org/2025/sqlite-autoconf-3490100.tar.gz";
  };

  boehm-gc = {
    version = "8.2.8";
    url = "https://github.com/ivmai/bdwgc.git";
    atomicops-url = "https://github.com/ivmai/libatomic_ops.git";
  };

  curl = {
    version = "8.17.0";
    url = "https://curl.se/download/curl-8.17.0.tar.xz";
  };

  libgit2 = {
    version = "1.9.0";
    url = "https://github.com/libgit2/libgit2/archive/refs/tags/v1.9.0.tar.gz";
  };

  libseccomp = {
    version = "2.5.5";
    url = "https://github.com/seccomp/libseccomp/releases/download/v2.5.5/libseccomp-2.5.5.tar.gz";
  };

  blake3 = {
    version = "1.8.2";
    url = "https://github.com/BLAKE3-team/BLAKE3/archive/refs/tags/1.8.2.tar.gz";
  };

  jq = {
    version = "1.7.1";
    url = "https://github.com/jqlang/jq.git";
  };

  googletest = {
    version = "1.15.2";
    url = "https://github.com/google/googletest.git";
  };

  rapidcheck = {
    url = "https://github.com/randomizedcoder/rapidcheck.git";
    branch = "nix-on-z";
  };
}
