{ pkgs, ... }:

{
  programs.pi = {
    enable = true;

    settings = {
      defaultProvider = "anthropic";
      theme = "dark";
      enableSkillCommands = true;
    };

    # Skills, commands and instructions, declared once and rendered for Pi by
    # flake-prompt. A prompt can also be a function of its arguments.
    flakePrompt.prompts = [
      {
        type = "skill";
        name = "code-review";
        description = "Review code against the house style.";
        body = "Prefer small, revertible commits. Name the failure mode first.";
      }
      {
        type = "command";
        name = "changelog";
        description = "Summarise commits since a tag.";
        body = "Commits: $ARGUMENTS";
      }
      {
        type = "instructions";
        name = "house";
        body = "Ask before adding a dependency.";
      }
    ];

    # Extensions are ordinary derivations; anything that is not already a Pi
    # package is packaged as one.
    extensions.notify = {
      enable = true;
      package = ./notify.ts;
    };

    # MCP servers: stdio entries can pull their CLI tools from Nix, HTTP
    # entries keep credentials out of the store with an environment reference.
    mcpServers = {
      filesystem = {
        command = pkgs.nodePackages."@modelcontextprotocol/server-filesystem";
        args = [ "." ];
        description = "Read and write files under the session directory.";
      };
      sentry = {
        url = "https://mcp.sentry.dev/mcp";
        exposure = "deferred";
        description = "Issue and trace lookup.";
      };
    };

    environment.required = [ "ANTHROPIC_API_KEY" ];
  };
}
