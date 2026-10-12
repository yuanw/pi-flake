{ lib }:

/*
  Clear skills/prompts/themes from a Pi package's manifest, keeping its
  extensions. Use when a published package also ships skills that
  flake-prompt installs: otherwise both install the same skill and Pi lists it
  twice.
*/
{
  pkgs,
  package,
  name ? package.pname or "pi-package",
  version ? package.version or "0",
}:
let
  override = pkgs.writeText "${name}-pi-override.json" (
    builtins.toJSON {
      pi = {
        skills = [ ];
        prompts = [ ];
        themes = [ ];
      };
    }
  );
in
pkgs.runCommand "pi-package-${name}-skills-off"
  {
    inherit name version;
    nativeBuildInputs = [ pkgs.jq ];
    passthru = package.passthru or { };
  }
  ''
    mkdir -p "$out"
    cp -a ${package}/. "$out/"
    chmod -R u+w "$out"
    if [ -f "$out/package.json" ]; then
      jq -s '.[0] * .[1]' "$out/package.json" ${override} > merged.json
      mv merged.json "$out/package.json"
    fi
  ''
