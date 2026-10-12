{
  lib,
  piLib,
  flakePrompt,
}:

{ pkgs, config, ... }:

let
  cfg = config.programs.pi.flakePrompt;

  rendered = piLib.renderPiFiles {
    inherit pkgs;
    inherit (cfg)
      prompts
      degradation
      ;
  };
in
{
  options.programs.pi.flakePrompt = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install flake-prompt prompts for Pi.";
    };

    prompts = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            type = "skill";
            name = "code-review";
            description = "Review code against the house style.";
            body = "…";
          }
          (inputs.my-prompts.lib.prompts.commitStyle { scope = "api"; })
        ]
      '';
      description = ''
        Canonical flake-prompt prompts: attrsets, or functions applied at the
        use site. Agents degrade to skills because Pi ships no subagent format.
      '';
    };

    degradation = lib.mkOption {
      type = lib.types.enum [
        "skill"
        "skip"
      ];
      default = "skill";
      description = "What to do with prompt types Pi cannot render natively.";
    };

    instructions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the merged instructions prompt as AGENTS.md.";
    };
  };

  config = lib.mkIf (config.programs.pi.enable && cfg.enable) {
    programs.pi = {
      resourceSkills = lib.attrValues rendered.skills;
      resourcePrompts = rendered.promptFiles;
      instructions = rendered.instructions;
    };
  };
}
