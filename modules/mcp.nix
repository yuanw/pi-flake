{ lib, piLib }:

{ config, ... }:

let
  cfg = config.programs.pi;

  exposureType = lib.types.enum [
    "codemode"
    "codemode-deferred"
    "deferred"
    "direct"
    "hidden"
  ];

  serverType = lib.types.submodule {
    freeformType = lib.types.attrsOf lib.types.anything;

    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether the server is written to mcp.json at all.";
      };

      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Set false to list the server but keep it disconnected.";
      };

      type = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "stdio"
            "http"
            "streamable-http"
          ]
        );
        default = null;
        description = "Transport. Pi infers stdio from command and HTTP from url.";
      };

      command = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.oneOf [
            lib.types.str
            lib.types.path
            lib.types.package
          ]
        );
        default = null;
        example = lib.literalExpression "pkgs.nodePackages.\"@modelcontextprotocol/server-filesystem\"";
        description = "stdio server executable.";
      };

      args = lib.mkOption {
        type = lib.types.listOf (
          lib.types.oneOf [
            lib.types.str
            lib.types.path
            lib.types.package
          ]
        );
        default = [ ];
        description = "Arguments for command.";
      };

      env = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.str
            lib.types.int
            lib.types.path
            lib.types.package
          ]
        );
        default = { };
        example = lib.literalExpression ''{ GITHUB_TOKEN = "''${GITHUB_TOKEN}"; }'';
        description = ''
          Server environment. Values may contain `''${NAME}` references so
          secrets stay out of the Nix store.
        '';
      };

      cwd = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Working directory. Relative paths resolve against the session directory.";
      };

      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Streamable HTTP endpoint.";
      };

      headers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = lib.literalExpression ''{ Authorization = "Bearer ''${DOCS_TOKEN}"; }'';
        description = "HTTP headers. Same `$NAME` interpolation as env.";
      };

      oauth = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "OAuth client configuration for HTTP servers.";
      };

      timeout = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Per-request timeout in seconds (Pi default 60).";
      };

      exposure = lib.mkOption {
        type = lib.types.nullOr exposureType;
        default = null;
        description = "How this server's tools reach the model.";
      };

      toolExposure = lib.mkOption {
        type = lib.types.attrsOf exposureType;
        default = { };
        example = lib.literalExpression ''{ search_code = "direct"; "delete_*" = "hidden"; }'';
        description = "Per-tool exposure overrides.";
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "One sentence shown to the model, used to rank the server's tools.";
      };

      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        example = lib.literalExpression "[ pkgs.python311Packages.mcp ]";
        description = ''
          Derivations a stdio server needs on PATH. Generates a wrapper that
          exports PATH and execs `command`.
        '';
      };
    };
  };

  validNames = lib.filterAttrs (
    name: server: server.enable && builtins.match "[A-Za-z0-9_-]+" name == null
  ) cfg.mcpServers;
in
{
  options.programs.pi.mcpServers = lib.mkOption {
    type = lib.types.attrsOf serverType;
    default = { };
    example = lib.literalExpression ''
      {
        filesystem = {
          command = pkgs.nodePackages."@modelcontextprotocol/server-filesystem";
          args = [ "." ];
        };
        docs = {
          url = "https://example.com/mcp";
          headers.Authorization = "Bearer ''${DOCS_TOKEN}";
          exposure = "deferred";
        };
      }
    '';
    description = "MCP servers written to mcp.json in the agent directory.";
  };

  config = lib.mkIf cfg.enable {
    programs.pi.assertions = [
      {
        assertion = validNames == { };
        message = "MCP server names may only use letters, digits, _ and -: ${lib.concatStringsSep ", " (builtins.attrNames validNames)}";
      }
      {
        assertion = lib.all (server: server.command != null || server.url != null) (
          lib.attrValues (lib.filterAttrs (_: s: s.enable) cfg.mcpServers)
        );
        message = "every enabled MCP server needs either `command` (stdio) or `url` (HTTP)";
      }
      {
        assertion = lib.all (server: !(server.packages != [ ] && server.url != null)) (
          lib.attrValues cfg.mcpServers
        );
        message = "programs.pi.mcpServers.packages only applies to stdio servers";
      }
    ];
  };
}
