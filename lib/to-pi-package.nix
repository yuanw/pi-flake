{ lib }:

/*
  Normalise anything that can carry extension code into a Pi package.

  Pi only runs peer-dependency mapping and resource discovery for things that
  look like packages, so a bare `.ts` derivation or a source tree without a
  manifest has to be wrapped. This replaces the per-host glue that otherwise
  accumulates around a Pi module.
*/
let
  mkPiExtension = import ./mk-pi-extension.nix { inherit lib; };
  anySuffix = suffixes: str: lib.any (suffix: lib.hasSuffix suffix str) suffixes;
in
{
  pkgs,
  name ? null,
  version ? null,
  package,
}:
let
  pkg =
    if lib.isDerivation package || builtins.isPath package then
      package
    else
      throw "toPiPackage: expected a derivation or path, got ${toString (lib.typeOf package)}";

  isDerivation = lib.isDerivation pkg;
  pathString = toString pkg;

  # For a derivation `<hash>-foo.ts` both pname and name carry `.ts`, so the
  # package name is derived from whatever arrives.
  name' =
    if name != null then
      name
    else if isDerivation then
      pkg.pname or pkg.name or "extension"
    else
      baseNameOf pathString;

  version' =
    if version != null then
      version
    else if isDerivation then
      pkg.version or "0.1.0"
    else
      "0.1.0";

  # Checked on the path string before touching the filesystem: a `.ts` store
  # path is a single file even when it has not been realised yet.
  isFile = anySuffix [
    ".ts"
    ".js"
    ".mjs"
    ".cjs"
  ] pathString;

  hasManifest = !isFile && builtins.pathExists "${pathString}/package.json";
  hasLayout = !isFile && builtins.pathExists "${pathString}/extensions";

  mk = args: mkPiExtension ({ inherit pkgs; } // args);
in
if isFile then
  mk {
    pname = lib.removeSuffix ".js" (lib.removeSuffix ".ts" name');
    version = version';
    entrypoint = pkg;
  }
else if hasManifest || hasLayout then
  pkg
else
  # Source tree of extension files, no manifest, no layout.
  mk {
    pname = name';
    inherit version';
    src = pkgs.runCommand "pi-src-${name'}" { } ''
      mkdir -p "$out"
      cp -a ${pkg}/. "$out/"
    '';
  }
