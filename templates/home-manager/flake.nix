{
  description = "Pi configuration with flake-prompt skills, MCP servers and extension packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";

    # Follow this flake's inputs to avoid two copies of nixpkgs and Pi:
    #   inputs.pi-flake.inputs.llm-agents.follows = "llm-agents";
    pi-flake.url = "github:yuanw/pi-flake";
    pi-flake.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      pi-flake,
      ...
    }:
    {
      homeConfigurations.example = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        modules = [
          ./home.nix
          pi-flake.homeManagerModules.default
          {
            home = {
              username = "me";
              homeDirectory = "/Users/me";
              stateVersion = "25.05";
            };
          }
        ];
      };
    };
}
