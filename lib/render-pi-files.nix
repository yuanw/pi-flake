{ lib, flakePrompt }:

/*
  Bridge to flake-prompt's pi renderer.

  flake-prompt renders one canonical prompt set into every tool's native
  layout; here we take just the pi view of it and turn the fileset into store
  paths that `settings.json` can point at. Nothing is written per-file into
  the home directory, so a skill directory stays atomic and Pi's own
  discovery of ~/.pi/agent/skills is never required.

  Returns { skills, prompts, instructions, files }.
*/
let
  sanitize = str: builtins.replaceStrings [ "/" "@" ":" ] [ "-" "-" "-" ] str;
in
{
  pkgs,
  prompts,
  degradation ? "skill",
}:
let
  rendered = flakePrompt.renderFiles {
    inherit prompts;
    tools.pi = true;
    defaultDegradation = degradation;
  };

  agentPrefix = ".pi/agent/";

  files = lib.mapAttrs' (path: value: lib.nameValuePair (lib.removePrefix agentPrefix path) value) (
    lib.filterAttrs (path: _: lib.hasPrefix agentPrefix path) rendered
  );

  # A fileset entry is { text } or { source, executable }.
  toPath =
    key: value:
    if value ? text && value.text != null then
      pkgs.writeText (sanitize "pi-${key}") value.text
    else if value ? source then
      value.source
    else
      throw "renderPiFiles: entry ${key} has neither text nor source";

  skillPrefix = "skills/";
  skillFiles = lib.filterAttrs (path: _: lib.hasPrefix skillPrefix path) files;

  byName = lib.foldlAttrs (
    acc: path: value:
    let
      rest = lib.removePrefix skillPrefix path;
      name = lib.head (lib.splitString "/" rest);
      file = lib.removePrefix "${name}/" rest;
    in
    acc
    // {
      "${name}" = (acc."${name}" or { }) // {
        "${file}" = value;
      };
    }
  ) { } skillFiles;

  skills = lib.mapAttrs (
    name: entries:
    pkgs.linkFarm "pi-skill-${sanitize name}" (
      lib.mapAttrsToList (file: value: {
        name = file;
        path = toPath "skill-${name}-${file}" value;
      }) entries
    )
  ) byName;

  promptFiles = lib.attrValues (
    lib.mapAttrs (key: value: toPath "prompt-${key}" value) (
      lib.filterAttrs (path: _: lib.hasPrefix "prompts/" path) files
    )
  );

  instructions = if files ? "AGENTS.md" then toPath "agents" files."AGENTS.md" else null;
in
{
  inherit
    skills
    promptFiles
    instructions
    ;
  files = files;
}
