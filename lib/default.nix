{ lib, flakePrompt }:

let
  builders = {
    # Package a single extension as a Pi package (package.json + extensions/).
    mkPiExtension = import ./mk-pi-extension.nix { inherit lib; };

    # Normalise any derivation or path into a loadable Pi package.
    toPiPackage = import ./to-pi-package.nix { inherit lib; };

    # Drop skills/prompts/themes from a package so flake-prompt owns them.
    stripPiResources = import ./strip-pi-resources.nix { inherit lib; };

    # Home Manager / NixOS module for one extension in a registry.
    mkPiExtensionModule = import ./mk-pi-extension-module.nix { inherit lib; };

    # A whole directory of extension sources as a package set.
    mkPiExtensionSet = import ./mk-pi-extension-set.nix { inherit lib; };

    # flake-prompt prompts -> Pi skill dirs, prompt files, AGENTS.md.
    renderPiFiles = import ./render-pi-files.nix {
      inherit
        lib
        flakePrompt
        ;
    };

    # programs.pi.mcpServers -> mcp.json derivation (or null).
    mkMcpConfig = import ./mcp.nix { inherit lib; };
  };

  # Pi resolves settings resource entries as strings.
  resourcePath =
    value: if lib.isDerivation value || builtins.isPath value then toString value else value;

  # Module-only keys that must not reach models.json. Freeform fields
  # (compat, custom headers, thinkingFormat, ...) survive.
  providerToModel =
    provider:
    lib.filterAttrs (_: v: v != null) (
      builtins.removeAttrs provider [
        "enable"
        "package"
        "packages"
        "runtimePackages"
        "environment"
        "passthru"
      ]
    );
in
builders
// {
  inherit
    resourcePath
    providerToModel
    ;
}
