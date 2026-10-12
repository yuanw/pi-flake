{ lib }:

{ config, ... }:

{
  config = lib.mkIf config.programs.pi.enable {
    environment.systemPackages = [ config.programs.pi.finalPackage ];
  };
}
