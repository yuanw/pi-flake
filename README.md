# pi-flake

Declarative [Pi](https://pi.dev) configuration in Nix: one `programs.pi` schema
for settings, providers, extensions, [flake-prompt](https://gitlab.com/fresheyeball/flake-prompt)
skills and commands, and MCP servers.

```nix
programs.pi = {
  enable = true;

  settings = { defaultProvider = "anthropic"; theme = "dark"; };

  providers.ollama = {
    baseUrl = "http://localhost:11434/v1";
    api = "openai-completions";
    models = [ { id = "qwen2.5-coder:7b"; } ];
  };

  # Extensions are ordinary derivations.
  extensions.notify = { enable = true; package = ./notify.ts; };

  # Skills, slash commands and instructions, declared once.
  flakePrompt.prompts = [ (import ./prompts) ];

  # MCP servers, with Nix-provided CLIs for stdio entries.
  mcpServers = {
    filesystem.command = pkgs.nodePackages."@modelcontextprotocol/server-filesystem";
    sentry = { url = "https://mcp.sentry.dev/mcp"; exposure = "deferred"; };
  };

  environment.required = [ "ANTHROPIC_API_KEY" ];
};
```

## Install

Home Manager (also `nixDarwinModules.default`, `nixosModules.default`):

```nix
# inputs
pi-flake.url = "github:yuanw/pi-flake";
pi-flake.inputs.nixpkgs.follows = "nixpkgs";
pi-flake.inputs.llm-agents.follows = "llm-agents";   # avoid a second Pi

# modules
[ pi-flake.homeManagerModules.default ]
```

Scaffold a single-user config: `nix flake init -t github:yuanw/pi-flake`.

## How the config reaches the user

The wrapper, not a host module, is the thing that installs config. On launch it
puts `settings.json`, `models.json`, `mcp.json` and `AGENTS.md` into
`$PI_CODING_AGENT_DIR` (default `~/.pi/agent`) as symlinks into the store, puts
extension/skill runtime dependencies on `PATH`, exports
`environment.variables`, and stops with a clear message if an
`environment.required` name is missing.

That means a bare `nix run`, a NixOS system and a Home Manager user all get the
same configuration, and Pi keeps `auth.json`, sessions and caches where it
normally puts them.

## Skills: flake-prompt, not a Pi-specific fork

Skill content lives in flake-prompt's canonical prompt format, so the same
declaration renders for Claude Code, Codex, opencode, Crush, Droid and Pi. The
bridge asks flake-prompt for Pi's view of your prompts and turns each one into
a store directory:

```nix
programs.pi.flakePrompt = {
  prompts = [
    { type = "skill"; name = "code-review"; description = "…"; body = "…"; }
    { type = "instructions"; name = "house"; body = "Ask before adding a dependency."; }
    (myPrompts.lib.prompts.commitStyle { scope = "api"; })   # a function of its arguments
  ];
  degradation = "skill";   # Pi has no subagent format, so agents become skills
};
```

Skills are listed in `settings.json`, so they stay in the store and never need
a directory of symlinks under `~/.pi/agent`. Set
`programs.pi.flakePrompt.enable = false` to let flake-prompt's own Home Manager
module handle Pi, or use `programs.pi.rawSkills` for skill trees you built
somewhere else.

## Extensions as packages

`programs.pi.extensions.<name>.package` accepts anything, and normalises it:

| What you pass | What Pi gets |
|---|---|
| a derivation marked `isPiPackage = true` | loaded as-is |
| a directory of `.ts`/`.js` sources | wrapped with a manifest and `pi.extensions = ["./extensions"]` |
| a single `.ts` file, source path or derivation | wrapped as a one-entry package |

Packing matters because Pi only runs peer-dependency mapping for things that
look like packages — a bare store path to a `.ts` file loads but cannot resolve
`@mariozechner/*` imports.

Everything except a marked package is *copied*, so a package with a big
`node_modules` costs a second store path. Pi packages you own should say so, and
the marker must be set in the derivation's source or with `extendDerivation`,
both of which rebuild nothing:

```nix
# packages/my-extensions/pi-cursor-agent.nix
buildNpmPackage { ... passthru.isPiPackage = true; }

# or, annotating someone else's package
lib.extendDerivation true { isPiPackage = true; } drv
```

Wrapping is never decided by reading inside a derivation: `package.json` is
checked by the builder, not by the evaluator, so the result cannot depend on
what happens to be in the store.

`runtimePackages` puts a CLI on `PATH` for the whole session (and is picked up
from `passthru.runtimePackages`, so a well-built package ships its own
dependencies). A whole registry is one line:

```nix
packages.extensions = pi-flake.lib.${system}.mkPiExtensionSet {
  pkgs = nixpkgs.legacyPackages.${system};
  dir = ./extensions;   # one package per subdirectory
};
```

and `lib.mkPiExtensionModule { name; package; }` publishes one entry of that set
as a typed `programs.pi.extensions.<name>` option. When a published package also
ships skills, keep flake-prompt as the installer:

```nix
programs.pi.extensions.ponytail.package =
  pi-flake.lib.${system}.stripPiResources { inherit pkgs; package = pkgs.pi-ponytail; };
```

## MCP

`programs.pi.mcpServers` writes `mcp.json`. Names must be `[A-Za-z0-9_-]+`;
`enable = false` drops a server, `enabled = false` lists it but leaves it
disconnected. Stdio entries take `command`, `args`, `env`, `cwd`; HTTP entries
take `url`, `headers`, `oauth`, plus `timeout`, `exposure`, `toolExposure`,
`description`.

The one thing worth knowing: `packages` exists because Pi does not expand
`env.PATH`. Give a stdio server the derivations it needs and a PATH-setting
wrapper is generated instead:

```nix
programs.pi.mcpServers."playwright" = {
  command = "npx";
  args = [ "-y" "@playwright/mcp" ];
  packages = [ pkgs.nodejs pkgs.ffmpeg ];
};
```

Secrets stay out of the store by referencing the environment:
`headers.Authorization = "Bearer \${GITHUB_TOKEN}"`.

## Library

```nix
lib.mkPiExtension { pkgs; pname; src ? ; entrypoint ? ; content ? ; runtimePackages ? [ ] ; piManifest ? { } ; }
lib.toPiPackage { pkgs; package; }         # any derivation/path -> Pi package
lib.stripPiResources { pkgs; package; }   # clear skills/prompts/themes from a manifest
lib.mkPiExtensionSet { pkgs; dir; }       # one package per subdirectory
lib.mkPiExtensionModule { name; … }       # module for one registry entry
lib.renderPiFiles { pkgs; prompts; … }     # flake-prompt fileset -> store paths
lib.mkMcpConfig { pkgs; servers; }        # mcp.json derivation
makePi { pkgs; modules; }                 # flake output: configured Pi, no host module
```

## Differences from nixpi

This repo is a sibling of [nixpi](https://github.com/mateusdcc/nixpi), not a
fork. The schema matches (`programs.pi.{enable,package,settings,providers,
extensions,packages,environment}`) so switching is mostly an input swap. What
is different, and why:

- **Skills come from flake-prompt.** nixpi has its own `mkPiSkill`/`customSkills`
  and writes skill directories into the home directory, which fights the
  installer that owns those directories today.
- **MCP is a first-class option.** nixpi has no MCP support, so `mcp.json` ends
  up as hand-written JSON in a host module.
- **Extension packaging is general.** nixpi's `mkPiExtension` needs the source
  layout spelled out; this repo normalises what you already have.
- **No legacy surface.** nixpi keeps deprecated `1.x` output names, profiles and
  a companion packages repo. Nothing here is kept for compatibility.

## Development

```console
$ nix flake check            # 8 checks: settings, mcp, skills, extensions, wrapper, placement, env, home-manager
$ nix flake check --all-systems --no-build
$ nix flake check -L         # verbose, including the Home Manager integration check
$ nix fmt
```

The `host` check evaluates a real `homeManagerConfiguration`, so the module
cannot silently break outside this repo's own evaluation path.

## Migrating from nixpi

1. Replace the input, keep the module import name:
   `nixpi.homeModules.default` → `pi-flake.homeModules.default`.
2. `programs.pi.flakePrompt.prompts` replaces `programs.agent-pm` for Pi and
   `programs.pi.customSkills`.
3. `programs.pi.mcpServers` replaces writing `mcp.json` from a host module.
4. `programs.pi.extensions.<name>.package` replaces the `mkPiExtensionModule`
   glue that wrapped packages by hand: delete the normalisation helper and its
   `stripNonExtensions`/`wrap*` wrappers. Keep `mics-skills` only for the tools
   that actually need whole-directory links.
5. If you set `programs.pi.settings.packages` or `settings.skills` by hand,
   remove them — the module rejects it with a message.
