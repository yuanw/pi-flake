{ lib }:

/*
  Home Manager / NixOS module for one entry in a Pi extension registry.

  Turns a derivation from `packages.pi-extensions.<name>` (or a source tree)
  into `programs.pi.extensions.<name>` with an `enable` switch, so downstream
  configs can flip extensions without touching packaging.
*/
{
  name,
  description ? null,
  package ? null,
  defaultPackage ? null,
  runtimePackages ? [ ],
  extraPackages ? [ ],
  extraOptions ? { },
  extraConfig ? (_cfg: { }),
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.pi.extensions.${name};

  resolvedPackage =
    if package != null then
      package
    else if defaultPackage != null then
      (if lib.isFunction defaultPackage then defaultPackage pkgs else defaultPackage)
    else
      null;
in
{
  options.programs.pi.extensions.${name} = {
    enable = lib.mkEnableOption (if description != null then description else "Pi ${name} extension");

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = resolvedPackage;
      description = "Package providing the ${name} extension.";
    };

    runtimePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = runtimePackages;
      description = "CLI packages needed by ${name} at runtime.";
    };
  }
  // extraOptions;

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.optionalAttrs (extraPackages != [ ]) {
        programs.pi.runtimePackages = extraPackages;
      })
      (extraConfig cfg)
    ]
  );
}
