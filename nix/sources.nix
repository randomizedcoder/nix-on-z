# Pinned source declarations for nix-on-z.
# SRI hashes computed via: nix-prefetch-url --unpack <url> | nix hash to-sri
{ fetchFromGitHub }:
{
  nix = {
    version = "2.35.0";
    src = fetchFromGitHub {
      owner = "NixOS";
      repo = "nix";
      rev = "7edcd0a24dc71abb7caa600527833ef540c1bc86";
      hash = "sha256-fybp46IQmRN7lEUTChc3MTqxmRutmDO4RNSPEQfJQsQ=";
    };
  };

  rapidcheck = {
    src = fetchFromGitHub {
      owner = "randomizedcoder";
      repo = "rapidcheck";
      rev = "dc32a8df762e8b2bd2287017f2e6a24bf86866ac";
      hash = "sha256-eYy+jLAgSA19+acJWarAa6qQ31cvbxHwwW4AzMkpVUg=";
    };
  };

  patches = [
    ../patches/0001-add-s390x-support.patch
    ../patches/0002-fix-functional-tests-unbound-NIX_STORE.patch
    ../patches/0003-add-shell-test-variable.patch
    ../patches/0004-fix-fetchGitSubmodules-recursive-transport.patch
    ../patches/0005-fix-sandbox-ownership-check-non-root.patch
    ../patches/0006a-fix-nix-develop-structured-attrs-outputs.patch
    ../patches/0006b-fix-nix-develop-non-flake-bashInteractive.patch
    ../patches/0007-fix-nested-sandboxing-skip-check.patch
  ];
}
