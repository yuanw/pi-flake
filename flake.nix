{
  description = "Declarative Pi coding agent: flake-prompt skills, MCP servers, and extension packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    flake-prompt.url = "gitlab:fresheyeball/flake-prompt";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      # x86_64-darwin is out of support in the nixpkgs this flake tracks.
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];

      eachSystem = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});

      # flake-prompt's renderer is system-independent; one copy for the flake.
      piLib = import ./lib {
        inherit lib;
        flakePrompt = inputs.flake-prompt.lib;
      };

      homeManagerTemplate = {
        path = ./templates/home-manager;
        description = "Home Manager configuration with flake-prompt skills and MCP servers";
      };

      modules = import ./modules {
        inherit
          lib
          piLib
          ;
        flakePrompt = inputs.flake-prompt.lib;

        # Override with programs.pi.package to reuse a Pi binary you already
        # have, or follow this flake's llm-agents input.
        defaultPiPackage =
          system:
          nixpkgs.legacyPackages.${system}.pi or (inputs.llm-agents.packages.${system}.pi
            or (throw "programs.pi.package is not set and no Pi binary was found")
          );
      };
    in
    {
      overlays.default = import ./flake/overlay.nix {
        inherit
          inputs
          lib
          piLib
          ;
      };

      # One programs.pi schema for every host integration.
      homeModules.pi = modules.homeManager;
      homeModules.default = modules.homeManager;
      homeManagerModules = modules.homeManagerByName;
      nixDarwinModules.pi = modules.nixDarwin;
      nixDarwinModules.default = modules.nixDarwin;
      nixosModules.pi = modules.nixos;
      nixosModules.default = modules.nixos;

      # Composition: import base to add programs.pi without host glue.
      piModules.base = modules.coreModules;

      # Build a configured Pi derivation directly.
      makePi = modules.makePi;

      # lib.<system>.{mkPiExtension,toPiPackage,mkPiExtensionSet,renderPiFiles,...}
      lib = lib.genAttrs systems (_: piLib);

      packages = eachSystem (
        system: pkgs:
        {
          default = modules.makePi {
            inherit pkgs;
            modules = [ { programs.pi.enable = true; } ];
          };
        }
        // (
          if builtins.pathExists ./extensions then
            {
              extensions = piLib.mkPiExtensionSet {
                inherit pkgs;
                dir = ./extensions;
              };
            }
          else
            { }
        )
      );

      apps = lib.genAttrs systems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/pi";
        };
      });

      checks = eachSystem (
        system: pkgs:
        import ./tests {
          inherit
            pkgs
            lib
            piLib
            modules
            system
            ;
          flakePrompt = inputs.flake-prompt.lib;
          homeManager = inputs.home-manager;
        }
      );

      templates = {
        default = homeManagerTemplate;
        home-manager = homeManagerTemplate;
      };

      formatter = eachSystem (system: pkgs: pkgs.nixfmt-rfc-style);
    };
}
