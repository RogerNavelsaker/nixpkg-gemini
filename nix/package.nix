{ bash, bun, bun2nix, gemini-cli-src, lib, makeWrapper, runCommand, symlinkJoin }:

let
  manifest = builtins.fromJSON (builtins.readFile ./package-manifest.json);
  packageVersion =
    manifest.package.version
    + lib.optionalString (manifest.package ? packageRevision) "-r${toString manifest.package.packageRevision}";
  licenseMap = {
    "MIT" = lib.licenses.mit;
    "Apache-2.0" = lib.licenses.asl20;
    "SEE LICENSE IN README.md" = lib.licenses.unfree;
  };
  resolvedLicense =
    if builtins.hasAttr manifest.meta.licenseSpdx licenseMap
    then licenseMap.${manifest.meta.licenseSpdx}
    else lib.licenses.unfree;
  aliasSpecs = map (
    alias:
    if builtins.isString alias then
      {
        name = alias;
        args = [ ];
      }
    else
      alias
  ) (manifest.binary.aliases or [ ]);
  renderAliasArgs = args: lib.concatMapStringsSep " " lib.escapeShellArg args;
  aliasOutputLinks = lib.concatMapStrings
    (
      alias:
      ''
        mkdir -p "${"$" + alias.name}/bin"
        cat > "${"$" + alias.name}/bin/${alias.name}" <<EOF
#!${lib.getExe bash}
exec "$out/bin/${manifest.binary.name}" ${renderAliasArgs alias.args} "\$@"
EOF
        chmod +x "${"$" + alias.name}/bin/${alias.name}"
      ''
    )
    aliasSpecs;
  cleanPackagingSource = lib.cleanSource ../.;
  sourceTree = runCommand "gemini-cli-packaging-source" { } ''
    mkdir -p "$out"
    cp -a ${cleanPackagingSource}/. "$out/"
    chmod -R u+w "$out"
    mkdir -p "$out/vendor"
    cp -a ${gemini-cli-src}/. "$out/vendor/gemini-cli"
  '';
  geminiCleanup = lib.optionalString (manifest.package.repo == "gemini-cli") ''
    geminiNodeModules="$out/share/${manifest.package.repo}/node_modules"
    find "$geminiNodeModules" -name '*.py' -delete
    find "$geminiNodeModules" -path '*/keytar/build' -prune -exec rm -rf '{}' +
  '';
  basePackage = bun2nix.writeBunApplication {
    pname = manifest.package.repo;
    version = packageVersion;
    packageJson = "${sourceTree}/package.json";
    src = sourceTree;
    dontUseBunBuild = true;
    dontUseBunCheck = true;
    startScript = ''
      bunx ${manifest.binary.upstreamName or manifest.binary.name} "$@"
    '';
    bunDeps = bun2nix.fetchBunDeps {
      bunNix = "${sourceTree}/bun.nix";
    };
    postInstall = ''
      ${geminiCleanup}
    '';
    meta = with lib; {
      description = manifest.meta.description;
      homepage = manifest.meta.homepage;
      license = resolvedLicense;
      mainProgram = manifest.binary.name;
      platforms = platforms.linux ++ platforms.darwin;
      broken = manifest.stubbed || !(builtins.pathExists ../bun.nix);
    };
  };
in
symlinkJoin {
  pname = manifest.binary.name;
  version = packageVersion;
  name = "${manifest.binary.name}-${packageVersion}";
  outputs = [ "out" ] ++ map (alias: alias.name) aliasSpecs;
  paths = [ basePackage ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    rm -rf "$out/bin"
    mkdir -p "$out/bin"
    makeWrapper "${basePackage}/bin/${manifest.package.repo}" "$out/bin/${manifest.binary.name}" \
      --set GEMINI_FORCE_FILE_STORAGE true
    ${aliasOutputLinks}
  '';
  meta = basePackage.meta;
}
