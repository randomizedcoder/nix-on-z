# Patched source bundle for native s390x builds.
#
# Fetches nix 2.35.0 source, applies all patches, and bundles with
# rapidcheck, build scripts, and patch files. Used by the sync app
# to rsync a deterministic source tree to the z machine.
{ pkgs, sources, self, zScripts }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "nix-s390x-source-bundle";
  version = sources.nix.version;
  src = sources.nix.src;
  patches = sources.patches;

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    mkdir -p $out/{nix-source,rapidcheck-source,scripts,patches}
    cp -r . $out/nix-source/
    cp -r ${sources.rapidcheck.src}/. $out/rapidcheck-source/
    ${builtins.concatStringsSep "\n    " (map (s: "cp ${s.script} $out/scripts/${s.name}.sh") zScripts.deployScripts)}
    cp ${self}/patches/*.patch $out/patches/
  '';
}
