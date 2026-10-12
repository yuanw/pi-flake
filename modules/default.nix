{
  lib,
  piLib,
  flakePrompt,
  defaultPiPackage,
}:

let
  # Host-independent option + config modules. Host modules only decide how the
  # configured Pi reaches the user; every generated file is placed by the
  # wrapper, so a Home Manager user and a bare system user get the same thing.
  coreModules = [
    (import ./core.nix {
      inherit
        lib
        piLib
        defaultPiPackage
        ;
    })
    (import ./skills.nix {
      inherit
        lib
        piLib
        flakePrompt
        ;
    })
    (import ./mcp.nix {
      inherit
        lib
        piLib
        ;
    })
  ];

  homeManagerModules = {
    imports = coreModules ++ [ (import ./host-home-manager.nix { inherit lib; }) ];
  };

  systemModules = {
    imports = coreModules ++ [ (import ./host-system.nix { inherit lib; }) ];
  };

  # Standalone Pi: same schema, evaluated without a host module system.
  makePi =
    {
      pkgs,
      modules ? [ ],
    }:
    (lib.evalModules {
      modules = coreModules ++ modules;
      specialArgs = { inherit pkgs; };
    }).config.programs.pi.finalPackage;
in
{
  inherit
    coreModules
    makePi
    ;

  homeManager = homeManagerModules;
  nixDarwin = systemModules;
  nixos = systemModules;

  homeManagerByName = {
    pi = homeManagerModules;
    default = homeManagerModules;
  };
}
