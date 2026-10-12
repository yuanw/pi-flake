{
  pkgs,
  lib,
  modules,
  system,
  homeManager,
}:

let
  config = homeManager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      modules.homeManager
      {
        home = {
          username = "me";
          homeDirectory = "/home/me";
          stateVersion = "25.05";
        };

        programs.pi = {
          enable = true;
          settings = {
            defaultProvider = "anthropic";
            theme = "dark";
          };
          mcpServers.docs.url = "https://example.com/mcp";
          mcpServers.filesystem = {
            command = pkgs.hello;
            packages = [ pkgs.gnused ];
          };
          environment.variables.PI_TELEMETRY = "0";
          environment.required = [ "ANTHROPIC_API_KEY" ];
        };
      }
    ];
  };

  cfg = config.config.programs.pi;
in
pkgs.runCommand "test-home-manager" { nativeBuildInputs = [ pkgs.jq ]; } ''
  # The configured Pi reaches the user, and every generated file is there.
  test -x ${cfg.finalPackage}/bin/pi
  jq -e '.defaultProvider == "anthropic" and .theme == "dark"' ${cfg.generatedSettingsFile}
  jq -e '.mcpServers.docs.url == "https://example.com/mcp"' ${cfg.generatedMcpFile}
  jq -e '.mcpServers.filesystem.command | test("pi-mcp-filesystem")' ${cfg.generatedMcpFile}

  # environment.required and variables are wired into the session.
  grep -q 'ANTHROPIC_API_KEY' ${cfg.finalPackage}/bin/pi
  grep -q 'export PI_TELEMETRY' ${cfg.finalPackage}/bin/pi

  touch $out
''
