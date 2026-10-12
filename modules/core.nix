{
  lib,
  piLib,
  defaultPiPackage,
}:

{ pkgs, config, ... }:

let
  cfg = config.programs.pi;

  enabledExtensions = lib.filterAttrs (_: ext: ext.enable) cfg.extensions;
  enabledProviders = lib.filterAttrs (_: prov: prov.enable) cfg.providers;

  # --- resources ---------------------------------------------------------

  # Anything that is not already a Pi package (single .ts entrypoint, bare
  # source directory) is normalised into one, so Pi's package loader and its
  # peer-dependency mapping apply.
  extensionPackages = lib.concatMap (
    ext:
    lib.optional (ext.package != null) (
      piLib.toPiPackage {
        inherit pkgs;
        name = ext.name or ext.pname or "extension";
        package = ext.package;
      }
    )
  ) (builtins.attrValues enabledExtensions);

  providerPackages = lib.concatMap (prov: lib.optional (prov.package != null) prov.package) (
    builtins.attrValues enabledProviders
  );

  runtimePackagesFrom =
    pkg:
    if lib.isDerivation pkg && pkg.passthru ? runtimePackages then
      pkg.passthru.runtimePackages
    else
      [ ];

  allResourcePackages = cfg.packages ++ extensionPackages ++ providerPackages ++ cfg.resourcePackages;

  allSkills = cfg.resourceSkills ++ cfg.rawSkills;

  runtimePackages = lib.unique (
    cfg.runtimePackages
    ++ (lib.concatMap (ext: ext.runtimePackages or [ ]) (builtins.attrValues enabledExtensions))
    ++ (lib.concatMap (prov: prov.runtimePackages or [ ]) (builtins.attrValues enabledProviders))
    ++ (lib.concatMap runtimePackagesFrom (
      allResourcePackages ++ allSkills ++ cfg.resourceExtensions ++ cfg.themes
    ))
  );

  resourcePath = piLib.resourcePath;

  # --- settings.json -----------------------------------------------------

  withoutNulls =
    value:
    if lib.isAttrs value && !lib.isDerivation value then
      lib.filterAttrs (_: v: v != null) (builtins.mapAttrs (_: withoutNulls) value)
    else if lib.isList value then
      map withoutNulls (lib.filter (v: v != null) value)
    else
      value;

  settingsFile = withoutNulls (
    lib.filterAttrs (_: v: !lib.isList v || v != [ ]) (
      cfg.settings
      // {
        packages = map resourcePath allResourcePackages;
        extensions = map resourcePath cfg.resourceExtensions;
        skills = map resourcePath allSkills;
        prompts = map resourcePath cfg.resourcePrompts;
        themes = map resourcePath cfg.themes;
      }
    )
  );

  generatedSettingsFile = pkgs.writeText "pi-settings.json" (builtins.toJSON settingsFile);

  # --- models.json -------------------------------------------------------

  generatedModelsFile =
    if enabledProviders != { } then
      pkgs.writeText "pi-models.json" (
        builtins.toJSON {
          providers = lib.mapAttrs (_: piLib.providerToModel) enabledProviders;
        }
      )
    else
      null;

  # --- mcp.json ----------------------------------------------------------

  generatedMcpFile = piLib.mkMcpConfig {
    inherit pkgs;
    servers = cfg.mcpServers;
  };

  generatedFiles = lib.filterAttrs (_: f: f != null) {
    "settings.json" = generatedSettingsFile;
    "models.json" = generatedModelsFile;
    "mcp.json" = generatedMcpFile;
    "AGENTS.md" = cfg.instructions;
  };

  # --- wrapper -----------------------------------------------------------

  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg (toString value)}") (
      lib.filterAttrs (_: v: v != null) cfg.environment.variables
    )
  );

  requiredChecks = lib.optionalString (cfg.environment.required != [ ]) ''
    missing=0
    for name in ${lib.escapeShellArgs cfg.environment.required}; do
      if [ -z "$(printenv "$name" 2>/dev/null || true)" ]; then
        printf 'pi-flake: required environment variable %s is not set\n' "$name" >&2
        missing=1
      fi
    done
    if [ "$missing" -ne 0 ]; then
      exit 1
    fi
  '';

  # `~` must expand against $HOME when Pi runs, not against the build user.
  agentDirDefault =
    if cfg.agentDirectory == "~" then
      "\"$HOME\""
    else if lib.hasPrefix "~/" cfg.agentDirectory then
      "\"$HOME/${lib.removePrefix "~/" cfg.agentDirectory}\""
    else
      lib.escapeShellArg cfg.agentDirectory;

  # Link one generated file into the agent directory. A regular file already
  # sitting there was edited by the user (Pi rewrites settings.json itself), so
  # keep one copy of it before the declarative version takes over.
  placeFile = name: ''
    dest="$agentDir/${name}"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
      [ -e "$dest.before-pi-flake" ] || cp -p "$dest" "$dest.before-pi-flake"
      printf 'pi-flake: %s was a local file; kept as %s.before-pi-flake\n' ${lib.escapeShellArg name} ${lib.escapeShellArg name} >&2
    fi
    ln -sfn ${lib.escapeShellArg (toString generatedFiles.${name})} "$dest"
  '';

  linkCommands = lib.concatMapStringsSep "\n" placeFile (builtins.attrNames generatedFiles);

  wrapper = pkgs.writeShellScriptBin "pi" ''
    set -eu

    ${lib.optionalString (runtimePackages != [ ]) ''
      export PATH="${lib.makeBinPath runtimePackages}:$PATH"
    ''}

    ${envExports}
    ${requiredChecks}

    # Materialise the declarative config in Pi's agent directory. Pi keeps
    # auth.json, sessions and caches there; only managed files are linked.
    agentDir="''${PI_CODING_AGENT_DIR:-${agentDirDefault}}"
    mkdir -p "$agentDir"
    ${linkCommands}

    exec ${cfg.package}/bin/pi "$@"
  '';

  finalPackage = pkgs.symlinkJoin {
    name = "pi-configured-${cfg.package.version or "custom"}";
    paths = [
      wrapper
      cfg.package
    ];
    meta.mainProgram = "pi";
    passthru = {
      inherit (cfg) package settings runtimePackages;
      inherit generatedSettingsFile generatedModelsFile generatedMcpFile;
      unwrapped = cfg.package;
    };
  };

  failedAssertions = lib.filter (x: !x.assertion) cfg.assertions;
  checkedFinalPackage =
    if failedAssertions != [ ] then
      throw "pi-flake: failed assertions:\n${
        lib.concatMapStringsSep "\n" (x: "- ${x.message}") failedAssertions
      }"
    else
      finalPackage;
in
{
  options.programs.pi = {
    enable = lib.mkEnableOption "declarative Pi configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPiPackage pkgs.stdenv.hostPlatform.system;
      defaultText = lib.literalExpression "the flake's pinned Pi binary";
      description = "Unwrapped Pi binary to configure.";
    };

    agentDirectory = lib.mkOption {
      type = lib.types.str;
      default = "~/.pi/agent";
      description = ''
        Pi's agent directory; generated files are symlinked into it on launch.
        An externally set `PI_CODING_AGENT_DIR` wins over this option.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = lib.literalExpression ''
        {
          defaultProvider = "anthropic";
          defaultModel = "claude-sonnet-4-5";
          theme = "dark";
        }
      '';
      description = ''
        Entries written to settings.json. The resource keys (`packages`,
        `extensions`, `skills`, `prompts`, `themes`) are managed by this
        module and must not be set here.
      '';
    };

    providers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.anything;
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to declare this provider in models.json.";
            };
            package = lib.mkOption {
              type = lib.types.nullOr lib.types.package;
              default = null;
              description = "Pi package that implements this provider.";
            };
            runtimePackages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = "CLI packages this provider needs at runtime.";
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          ollama = {
            baseUrl = "http://localhost:11434/v1";
            api = "openai-completions";
            apiKey = "ollama";
            models = [ { id = "qwen2.5-coder:7b"; } ];
          };
        }
      '';
      description = "Providers written to models.json, keyed by name.";
    };

    extensions = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.anything;
          options = {
            enable = lib.mkEnableOption "extension";
            name = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Package name override; defaults to the option name.";
            };
            package = lib.mkOption {
              type = lib.types.nullOr lib.types.package;
              default = null;
              description = ''
                Pi package, extension directory, or single `.ts`/`.js` file.
                Anything that is not already a Pi package is packaged as one.
              '';
            };
            runtimePackages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = "CLI packages placed on PATH for Pi.";
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression "{ notify.enable = true; }";
      description = "Enabled Pi extensions, keyed by name.";
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      example = lib.literalExpression ''
        [ "npm:@example/pi-tools@1.0.0" "git:github.com/example/pi-tools@v1" ]
      '';
      description = "Additional package sources for settings.packages.";
    };

    rawSkills = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      description = "Skill files or directories to add to settings.skills.";
    };

    themes = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      description = "Theme files or directories to add to settings.themes.";
    };

    runtimePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "CLI packages on PATH for the Pi wrapper.";
    };

    instructions = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "AGENTS.md file. Usually set by the flake-prompt bridge.";
    };

    environment = {
      variables = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.str
            lib.types.int
            lib.types.bool
            lib.types.path
          ]
        );
        default = { };
        example = lib.literalExpression ''{ PI_TELEMETRY = "0"; }'';
        description = "Environment variables exported by the wrapper.";
      };
      required = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = lib.literalExpression ''[ "OPENAI_API_KEY" ]'';
        description = "Variable names that must already exist before Pi starts.";
      };
    };

    # Accumulators for other modules; not part of the public schema.
    resourcePackages = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      internal = true;
    };
    resourceExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      internal = true;
    };
    resourceSkills = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      internal = true;
    };
    resourcePrompts = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      internal = true;
    };

    assertions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            assertion = lib.mkOption {
              type = lib.types.bool;
              description = "Whether the condition holds.";
            };
            message = lib.mkOption {
              type = lib.types.str;
              description = "Message shown when the assertion fails.";
            };
          };
        }
      );
      default = [ ];
      description = "Assertions checked before the configured Pi package is built.";
    };

    finalPackage = lib.mkOption {
      type = lib.types.package;
      default = if cfg.enable then checkedFinalPackage else cfg.package;
      description = "Configured Pi: wrapper, runtime dependencies, generated config.";
    };

    generatedSettingsFile = lib.mkOption {
      type = lib.types.package;
      default = generatedSettingsFile;
      description = "Generated settings.json.";
    };
    generatedModelsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = generatedModelsFile;
      description = "Generated models.json, or null when no providers are declared.";
    };
    generatedMcpFile = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = generatedMcpFile;
      description = "Generated mcp.json, or null when no servers are declared.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.pi = {
      settings.enableSkillCommands = lib.mkDefault true;
      assertions = [
        {
          assertion = !(cfg.settings ? packages) && !(cfg.settings ? skills);
          message = ''
            programs.pi.settings must not set `packages` or `skills`; use
            programs.pi.packages, programs.pi.extensions,
            programs.pi.flakePrompt or programs.pi.rawSkills instead.
          '';
        }
      ];
    };
  };
}
