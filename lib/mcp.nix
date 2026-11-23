{ lib }:

/*
  programs.pi.mcpServers -> mcp.json derivation, or null when no server is
  enabled. Stdio servers that need CLI tools get a PATH-setting wrapper: Pi
  does not expand `env.PATH`, so prefixing it there would silently break.

  `target = "cursor"` writes the shape Cursor's agent reads: the same
  `mcpServers` entries minus Pi's exposure keys, and without the servers Pi
  keeps listed but disconnected.
*/
{
  pkgs,
  servers,
  target ? "pi",
}:
let
  forCursor = target == "cursor";

  enabled = lib.filterAttrs (_: server: server.enable && (!forCursor || server.enabled)) servers;

  toCommand = value: if lib.isDerivation value then lib.getExe value else toString value;

  # Pi expands `$NAME` and `${NAME}` against the environment when it launches a
  # server, which is how secrets stay out of the store. Cursor reads the same
  # file but substitutes with `${env:NAME}`, so a shared value is rewritten.
  substituteEnv =
    value:
    if !forCursor then
      toString value
    else
      lib.concatStrings (
        map (chunk: if builtins.isList chunk then "\${env:${builtins.head chunk}}" else chunk) (
          # Every `$NAME` / `${NAME}` reference becomes a capture group.
          builtins.split "\\$\\{?([A-Za-z_][A-Za-z0-9_]*)\\}?" (toString value)
        )
      );

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
          oauth
          timeout
          exposure
          toolExposure
          description
          ;
        command = commandValue;
        args = if server.args == [ ] then null else map toCommand server.args;
        env = if server.env == { } then null else lib.mapAttrs (_: v: substituteEnv v) server.env;
        headers =
          if server.headers == { } then null else lib.mapAttrs (_: v: substituteEnv v) server.headers;
        cwd = server.cwd;
      };

      # Cursor knows none of Pi's exposure keys. `type` never travels either:
      # Cursor infers the transport from `command`/`url`, and a value it does
      # not know (e.g. `streamable-http`) makes it discard the whole file.
      cursorDrop = [
        "exposure"
        "toolExposure"
        "description"
        "type"
      ];

      shared = if forCursor then lib.removeAttrs json cursorDrop else json;
    in
    if server.enabled then
      if server.url != null then lib.removeAttrs shared [ "command" ] else shared
    else
      { enabled = false; };
in
if enabled == { } then
  null
else
  pkgs.writeText "${target}-mcp.json" (builtins.toJSON { mcpServers = lib.mapAttrs entry enabled; })
