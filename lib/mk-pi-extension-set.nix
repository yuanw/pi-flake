{ lib }:

/*
  One Pi package per entry of `dir`.

  Gives a repo of extension sources a package set without a per-extension
  default.nix, which is where Pi extension registries usually rot. Layout,
  manifest and single-file cases are handled by toPiPackage.
*/
{
  pkgs,
  dir,
  overrides ? { },
}:
let
  toPiPackage = import ./to-pi-package.nix { inherit lib; };
in
lib.mapAttrs (
  name: _type:
  toPiPackage {
    inherit
      pkgs
      name
      ;
    package = dir + "/${name}";
  }
) (lib.filterAttrs (_: type: type == "directory" || type == "regular") (builtins.readDir dir))
// overrides
