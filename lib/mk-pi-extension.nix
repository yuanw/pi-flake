{ lib }:

{
  pkgs,
  pname,
  version ? "0.1.0",
  description ? "Pi extension package: ${pname}",
  src ? null,
  entrypoint ? null,
  content ? null,
  runtimePackages ? [ ],
  fileName ? null,
  piManifest ? { },
  meta ? { },
}:
let
  sources = lib.filter (x: x != null) [
    src
    entrypoint
    content
  ];

  source =
    if builtins.length sources == 1 then
      builtins.head sources
    else
      throw "mkPiExtension: exactly one of `src`, `entrypoint` or `content` is required for ${pname}";

  manifest = {
    name = pname;
    inherit version;
    keywords = [ "pi-package" ];
    pi.extensions = [ "./extensions" ];
  }
  // piManifest;

  manifestFile = pkgs.writeText "${pname}-package.json" (builtins.toJSON manifest);

  isDirectory = src != null;
  file = if content != null then pkgs.writeText "${pname}-index.ts" content else source;

  # What the extension ends up called under extensions/. Store paths carry a
  # hash prefix and derivations often carry a version in their name, so callers
  # can pass `fileName` explicitly.
  extensionFileName =
    if fileName != null then
      fileName
    else if lib.isDerivation file then
      file.name
    else
      baseNameOf (toString file);
in
pkgs.runCommand "pi-extension-${pname}-${version}"
  {
    inherit pname version;
    nativeBuildInputs = [ pkgs.jq ];
    passthru = {
      isPiPackage = true;
      inherit runtimePackages;
    };
    meta = meta // {
      description = meta.description or description;
    };
  }
  ''
    mkdir -p "$out/extensions"
    ${
      if isDirectory then
        ''
          # A derivation output can be one file even when its store path looks
          # like a directory, so let the filesystem decide.
          if [ -f ${source} ]; then
            cp ${source} "$out/extensions/${extensionFileName}"
          else
            cp -a ${source}/. "$out/"
            chmod -R u+w "$out"
            # Trees that keep their .ts files at the root need them under
            # extensions/ for Pi's conventional discovery.
            if [ -z "$(find "$out/extensions" -type f 2>/dev/null)" ]; then
              find "$out" -maxdepth 1 -type f \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' \) \
                -exec mv -t "$out/extensions" {} +
            fi
          fi
        ''
      else
        ''
          cp ${file} "$out/extensions/${extensionFileName}"
        ''
    }

    # The package's own manifest wins: its `pi.extensions` points at real files.
    if [ -f "$out/package.json" ]; then
      jq -s '.[1] * .[0]' "$out/package.json" ${manifestFile} > merged.json
      mv merged.json "$out/package.json"
    else
      cp ${manifestFile} "$out/package.json"
    fi
  ''
