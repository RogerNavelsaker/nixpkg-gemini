{
  bash,
  buildNpmPackage,
  gemini-cli-src,
  lib,
  makeBinaryWrapper,
  nodejs_20,
  symlinkJoin,
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./package-manifest.json);
  packageJson = builtins.fromJSON (builtins.readFile "${gemini-cli-src}/package.json");
  packageVersion =
    packageJson.version
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
  basePackage = buildNpmPackage {
    pname = manifest.package.repo;
    version = packageVersion;
    src = gemini-cli-src;
    npmDepsFetcherVersion = 2;
    npmDepsHash = "sha256-YfUPuXnmVbxMJ0wFYwWGm06h6/nlT/nreVhHg8A00OU=";
    npmFlags = [ "--omit=optional" ];
    npmBuildScript = "bundle";
    nativeBuildInputs = [ makeBinaryWrapper ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/libexec/gemini-cli"
      cp -rL bundle "$out/libexec/gemini-cli/"
      cp package.json README.md LICENSE "$out/libexec/gemini-cli/"

      mkdir -p "$out/bin"
      makeBinaryWrapper ${lib.getExe nodejs_20} "$out/bin/${manifest.binary.name}" \
        --set GEMINI_FORCE_FILE_STORAGE true \
        --add-flags "$out/libexec/gemini-cli/bundle/gemini.js"

      runHook postInstall
    '';

    meta = with lib; {
      description = manifest.meta.description;
      homepage = manifest.meta.homepage;
      license = resolvedLicense;
      mainProgram = manifest.binary.name;
      platforms = platforms.linux ++ platforms.darwin;
    };
  };
in
symlinkJoin {
  pname = manifest.binary.name;
  version = packageVersion;
  name = "${manifest.binary.name}-${packageVersion}";
  outputs = [ "out" ] ++ map (alias: alias.name) aliasSpecs;
  paths = [ basePackage ];
  postBuild = ''
    ${aliasOutputLinks}
  '';
  meta = basePackage.meta;
}
