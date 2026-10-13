{
  pkgs,
  lib,
  piLib,
  modules,
  system,
  flakePrompt,
  homeManager,
}:

let
  evalPi =
    extra:
    (lib.evalModules {
      modules = modules.coreModules ++ extra;
      specialArgs = { inherit pkgs; };
    }).config.programs.pi;

  # One Pi config per feature under test.
  settingsCfg = evalPi [
    {
      programs.pi = {
        enable = true;
        settings = {
          defaultProvider = "anthropic";
          theme = "dark";
        };
        packages = [ "npm:@example/pi-tools@1.0.0" ];
      };
    }
  ];

  mcpCfg = evalPi [
    {
      programs.pi = {
        enable = true;
        mcpServers = {
          filesystem = {
            command = pkgs.hello;
            args = [ "." ];
            packages = [ pkgs.gnused ];
            env.PATH_HINT = "keep";
          };
          docs = {
            url = "https://example.com/mcp";
            headers.Authorization = "Bearer $DOCS_TOKEN";
            exposure = "deferred";
            toolExposure.search_code = "direct";
            timeout = 30;
          };
          removed = {
            command = "nope";
            enable = false;
          };
          kept = {
            command = "echo";
            enabled = false;
          };
        };
      };
    }
  ];

  skillsCfg = evalPi [
    {
      programs.pi = {
        enable = true;
        flakePrompt.prompts = [
          {
            type = "skill";
            name = "demo";
            description = "A demo skill.";
            body = "Do the demo.";
            files."references/checklist.md".text = "Check it.";
          }
          {
            type = "command";
            name = "changelog";
            description = "Write a changelog.";
            body = "Entries: $ARGUMENTS";
          }
          {
            type = "instructions";
            name = "house";
            body = "Prefer small commits.";
          }
        ];
      };
    }
  ];

  extensionPackage = pkgs.writeText "demo-extension.ts" ''
    export default (pi: unknown) => pi.registerCommand("demo", {});
  '';

  # What core wraps for programs.pi.extensions.demo.package.
  singleFilePackageInput = pkgs.runCommand "pi-slow-mode.ts-0-unstable-2026-09-22" { }
    ''cp ${./fixture.ts} $out'';

  demoPackage = piLib.toPiPackage {
    inherit pkgs;
    package = extensionPackage;
  };

  # Source paths, not just derivations: single file and bare directory trees
  # both have to come out as Pi packages.
  pathPackage = piLib.toPiPackage {
    inherit pkgs;
    package = ./fixture.ts;
  };

  dirPackage = piLib.toPiPackage {
    inherit pkgs;
    package = ./ext-src;
  };

  # The same derivation, normalised: what `packages` has to list.
  singleFilePackage = piLib.toPiPackage {
    inherit pkgs;
    package = singleFilePackageInput;
  };

  extensionCfg = evalPi [
    {
      programs.pi = {
        enable = true;
        extensions.demo = {
          enable = true;
          package = extensionPackage;
          runtimePackages = [ pkgs.jq ];
        };
        extensions.source = {
          enable = true;
          package = ./fixture.ts;
        };
        extensions.sourceDir = {
          enable = true;
          package = ./ext-src;
        };
        extensions.singleFile = {
          enable = true;
          package = singleFilePackageInput;
        };
        providers.ollama = {
          baseUrl = "http://localhost:11434/v1";
          api = "openai-completions";
          apiKey = "ollama";
          models = [ { id = "qwen2.5-coder:7b"; } ];
        };
      };
    }
  ];

  # Everything the wrapper has to place, for the placement test.
  fullCfg = evalPi [
    {
      programs.pi = {
        enable = true;
        settings.defaultProvider = "anthropic";
        providers.ollama.baseUrl = "http://localhost:11434/v1";
        mcpServers.docs.url = "https://example.com/mcp";
        runtimePackages = [ pkgs.jq ];
        flakePrompt.prompts = [
          {
            type = "instructions";
            name = "house";
            body = "Prefer small commits.";
          }
        ];
      };
    }
  ];

  wrapper = lib.getExe fullCfg.finalPackage;

in
{
  # settings.json carries the user's scalar keys, the managed resource arrays,
  # and nothing empty.
  settings = pkgs.runCommand "test-settings" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq -e '.defaultProvider == "anthropic" and .theme == "dark"' ${settingsCfg.generatedSettingsFile}
    jq -e '.packages == ["npm:@example/pi-tools@1.0.0"]' ${settingsCfg.generatedSettingsFile}
    jq -e '.enableSkillCommands == true' ${settingsCfg.generatedSettingsFile}
    jq -e 'has("skills") | not' ${settingsCfg.generatedSettingsFile}
    jq -e 'has("extensions") | not' ${settingsCfg.generatedSettingsFile}
    touch $out
  '';

  # mcp.json: wrappers for PATH-dependent stdio servers, HTTP entries kept
  # separate, and `enabled = false` keeps a server listed but disconnected.
  mcp = pkgs.runCommand "test-mcp" { nativeBuildInputs = [ pkgs.jq ]; } ''
    mcp=${mcpCfg.generatedMcpFile}
    jq -e '.mcpServers | has("removed") | not' $mcp
    jq -e '.mcpServers.kept == { "enabled": false }' $mcp
    jq -e '.mcpServers.filesystem | has("command") and has("url") | not' $mcp
    jq -e '.mcpServers.filesystem.args == ["."]' $mcp
    jq -e '.mcpServers.docs.url == "https://example.com/mcp"' $mcp
    jq -e '.mcpServers.docs | has("command") | not' $mcp
    jq -e '.mcpServers.docs.headers.Authorization == "Bearer $DOCS_TOKEN"' $mcp
    jq -e '.mcpServers.docs.exposure == "deferred"' $mcp
    jq -e '.mcpServers.docs.toolExposure.search_code == "direct"' $mcp
    jq -e '.mcpServers.docs.timeout == 30' $mcp
    # stdio servers that need extra CLIs get a generated PATH wrapper.
    jq -e '.mcpServers.filesystem.command | test("/bin/pi-mcp-filesystem$")' $mcp
    touch $out
  '';

  # The flake-prompt bridge: skill dirs (including extra files), prompt files
  # for commands, and one merged AGENTS.md.
  skills = pkgs.runCommand "test-skills" { nativeBuildInputs = [ pkgs.jq ]; } ''
    settings=${skillsCfg.generatedSettingsFile}
    jq -e '.skills == ["${builtins.head skillsCfg.resourceSkills}"]' $settings
    jq -e '.prompts == ["${builtins.head skillsCfg.resourcePrompts}"]' $settings

    skill=${builtins.head skillsCfg.resourceSkills}
    grep -q 'name: "demo"' $skill/SKILL.md
    grep -q 'Do the demo.' $skill/SKILL.md
    grep -q 'Check it.' $skill/references/checklist.md
    grep -q 'Entries: $ARGUMENTS' ${builtins.head skillsCfg.resourcePrompts}
    grep -q 'Prefer small commits.' ${skillsCfg.instructions}
    touch $out
  '';

  # An extension registry that only declares a name and a package.
  extensions = pkgs.runCommand "test-extensions" { nativeBuildInputs = [ pkgs.jq ]; } ''
    settings=${extensionCfg.generatedSettingsFile}
    for p in ${demoPackage} ${pathPackage} ${dirPackage} ${singleFilePackage}; do
      jq -e --arg p "$p" '.packages | index($p) != null' $settings
    done
    jq -e '.packages | length == 4' $settings
    jq -e '.pi.extensions == ["./extensions"]' ${singleFilePackage}/package.json
    find ${singleFilePackage}/extensions -name '*.ts' | grep -q .
    jq -e '.pi.extensions == ["./extensions"] and (.keywords | index("pi-package"))' ${demoPackage}/package.json
    test -f ${demoPackage}/extensions/demo-extension.ts
    jq -e '.packages | index("${pathPackage}") != null' $settings
    test -f ${pathPackage}/extensions/fixture.ts
    test -f ${dirPackage}/extensions/tool.ts
    jq -e '.pi.extensions == ["./extensions"]' ${dirPackage}/package.json

    jq -e '.providers.ollama.baseUrl == "http://localhost:11434/v1"' ${extensionCfg.generatedModelsFile}
    jq -e '.providers.ollama | has("enable") and has("package") | not' ${extensionCfg.generatedModelsFile}
    jq -e '.providers.ollama.models[0].id == "qwen2.5-coder:7b"' ${extensionCfg.generatedModelsFile}
    touch $out
  '';

  # The wrapper, not a host module, places every generated file.
  wrapperPlacement = pkgs.runCommand "test-wrapper" { } ''
    for name in settings.json models.json mcp.json AGENTS.md; do
      grep -q "agentDir/$name" ${wrapper}
    done
    grep -q 'ln -sfn' ${wrapper}
    grep -q 'jq-.*-bin/bin' ${wrapper}
    grep -q 'PI_CODING_AGENT_DIR' ${wrapper}
    touch $out
  '';

  # Home Manager wiring: the module must work inside a real home configuration.
  host = import ./host.nix {
    inherit
      pkgs
      lib
      modules
      system
      ;
    inherit homeManager;
  };

  # The wrapper places config in the *running* user's home and never destroys
  # a hand-edited file silently.
  placement =
    let
      cfg = evalPi [
        {
          programs.pi = {
            enable = true;
            package = pkgs.writeShellScriptBin "pi" "exit 0";
            settings.defaultProvider = "x";
          };
        }
      ];
    in
    pkgs.runCommand "test-placement" { nativeBuildInputs = [ pkgs.jq ]; } ''
      home=$(mktemp -d)
      mkdir -p "$home/.pi/agent"
      printf '{"user-edited":true}' > "$home/.pi/agent/settings.json"

      HOME="$home" ${lib.getExe cfg.finalPackage}

      test -L "$home/.pi/agent/settings.json"
      jq -e '.defaultProvider == "x"' "$home/.pi/agent/settings.json"
      jq -e '.["user-edited"] == true' "$home/.pi/agent/settings.json.before-pi-flake"

      # PI_CODING_AGENT_DIR wins, and $HOME must be read at run time.
      target=$(mktemp -d)
      HOME="$home" PI_CODING_AGENT_DIR="$target" ${lib.getExe cfg.finalPackage}
      test -L "$target/settings.json"

      real=$(mktemp -d)
      HOME="$real" ${lib.getExe cfg.finalPackage}
      test -L "$real/.pi/agent/settings.json"
      touch $out
    '';

  # Required environment names must be checked before Pi starts.
  environment =
    let
      cfg = evalPi [
        {
          programs.pi = {
            enable = true;
            environment.required = [ "OPENAI_API_KEY" ];
            runtimePackages = [ pkgs.hello ];
          };
        }
      ];
    in
    pkgs.runCommand "test-environment" { } ''
      w=${lib.getExe cfg.finalPackage}
      grep -q 'OPENAI_API_KEY' $w
      grep -q 'export PI_TELEMETRY' ${
        (evalPi [
          {
            programs.pi = {
              enable = true;
              environment.variables.PI_TELEMETRY = "0";
            };
          }
        ]).finalPackage
      }/bin/pi
      touch $out
    '';
}
