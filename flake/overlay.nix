{
  inputs,
  lib,
  piLib,
}:

final: prev:

{
  # Lets programs.pi.package default to a Pi binary inside the caller's own
  # package set instead of this flake's pinned copy.
  pi = inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}.pi or null;

  # Extension sources shipped by this flake, if any.
  pi-extensions =
    if builtins.pathExists ../extensions then
      piLib.mkPiExtensionSet {
        pkgs = final;
        dir = ../extensions;
      }
    else
      { };
}
