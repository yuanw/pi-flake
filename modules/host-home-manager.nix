{ lib }:

{ config, ... }:

{
  config = lib.mkIf config.programs.pi.enable {
    home.packages = [ config.programs.pi.finalPackage ];

    # Visible to login shells so `programs.pi.environment.required` checks pass
    # when the values come from a session environment or a secrets manager.
    home.sessionVariables = lib.mapAttrs (_: value: toString value) (
      lib.filterAttrs (_: v: v != null) config.programs.pi.environment.variables
    );
  };
}
