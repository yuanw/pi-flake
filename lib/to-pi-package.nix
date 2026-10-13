{ lib }:

/*
  Normalise anything that can carry extension code into a Pi package.

  Pi only runs peer-dependency mapping and resource discovery for things that
  look like packages, so a bare `.ts` derivation or a source tree without a
  manifest has to be wrapped. This replaces the per-host glue that otherwise
  accumulates around a Pi module.
*/
{
  pkgs,
  name ? null,
  version ? null,
  package,
}:
let
  mkPiExtension = import ./mk-pi-extension.nix { inherit lib; };

  pkg =
    if lib.isDerivation package || builtins.isPath package then
      package
    else
      throw "toPiPackage: expected a derivation or path, got ${toString (lib.typeOf package)}";

  cleanName = lib.getName pkg;

  name' =
    if name != null then
      name
    else if lib.isDerivation pkg then
      cleanName
    else
      baseNameOf (toString pkg);

  # Names are the weak point of this whole job. A source file ends in `.ts`; a
  # derivation that installs one file usually carries `.ts-<version>` in its
  # name. Both need stripping for the package name and keeping for the file.
  extSuffix =
    lib.findFirst
      (suffix: lib.hasSuffix suffix name')
      null
      [
        ".ts"
        ".js"
        ".mjs"
        ".cjs"
      ];

  fileName = if extSuffix != null then name' else null;

  pname =
    if extSuffix != null then lib.removeSuffix extSuffix name' else name';

  version' =
    if version != null then
      version
    else if lib.isDerivation pkg then
      pkg.version or "0.1.0"
    else
      "0.1.0";

  # False for an unrealised derivation, which is the case we are trying to fix.
  isPiPackage = lib.isDerivation pkg && builtins.pathExists "${toString pkg}/package.json";
in
if isPiPackage then
  pkg
else
  # Directories, single files and bare source trees all copy through the same
  # builder; whether `src` lands as one file or a tree is decided in the shell,
  # because a store path cannot tell you which it is.
  mkPiExtension {
    inherit pkgs fileName;
    inherit pname;
    version = version';
    src = pkg;
  }
