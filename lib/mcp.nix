{ lib }:

/*
  programs.pi.mcpServers -> mcp.json derivation, or null when no server is
  enabled. Stdio servers that need CLI tools get a PATH-setting wrapper: Pi
  does not expand `env.PATH`, so prefixing it there would silently break.
*/
{ pkgs, servers }:
let
  enabled = lib.filterAttrs (_: server: server.enable) servers;

  toCommand = value: if lib.isDerivation value then lib.getExe value else toString value;

  entry =
    name: server:
    let
      wrapper = pkgs.writeShellScriptBin "pi-mcp-${name}" ''
        export PATH="${lib.makeBinPath server.packages}:$PATH"
        exec ${toCommand server.command} "$@"
      '';

      commandValue =
        if server.command == null then
          null
        else if server.packages != [ ] then
          toCommand wrapper
        else
          toCommand server.command;

      json = lib.filterAttrs (_: v: v != null && v != [ ] && v != { }) {
        inherit (server)
          type
          url
          headers
          oauth
          timeout
          exposure
          toolExposure
          description
          ;
        command = commandValue;
        args = if server.args == [ ] then null else map toCommand server.args;
        env = if server.env == { } then null else lib.mapAttrs (_: v: toString v) server.env;
        cwd = server.cwd;
      };
    in
    if server.enabled then
      if server.url != null then lib.removeAttrs json [ "command" ] else json
    else
      { enabled = false; };
in
if enabled == { } then
  null
else
  pkgs.writeText "pi-mcp.json" (builtins.toJSON { mcpServers = lib.mapAttrs entry enabled; })
