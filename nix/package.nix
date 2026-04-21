{
  bash,
  bun,
  buildNpmPackage,
  gemini-cli-src,
  npmDepsHash,
  lib,
  makeWrapper,
  nodejs,
  perl,
  symlinkJoin,
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./package-manifest.json);
  sourceCliPackage = builtins.fromJSON (builtins.readFile "${gemini-cli-src}/packages/cli/package.json");
  packageVersion =
    sourceCliPackage.version
    + lib.optionalString (manifest.package ? packageRevision) "-r${toString manifest.package.packageRevision}";

  applyDownstreamPatches = builtins.toFile "apply-downstream-patches.sh" ''
    replace_if_present() {
      local file="$1"
      local old="$2"
      local new="$3"

      if grep -Fq "$old" "$file"; then
        OLD="$old" NEW="$new" perl -0pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/gs' "$file"
      fi
    }

    settings_schema="$1/packages/cli/src/config/settingsSchema.ts"
    interactive_cli="$1/packages/cli/src/interactiveCli.tsx"
    app_container="$1/packages/cli/src/ui/AppContainer.tsx"
    shell_service="$1/packages/core/src/services/shellExecutionService.ts"
    shell_service_test="$1/packages/core/src/services/shellExecutionService.test.ts"
    core_policy_config="$1/packages/core/src/policy/config.ts"

    old="label: 'Enable Auto Update',
        category: 'General',
        requiresRestart: false,
        default: true,"
    new="label: 'Enable Auto Update',
        category: 'General',
        requiresRestart: false,
        default: false,"
    replace_if_present "$settings_schema" "$old" "$new"

    old="label: 'Enable Auto Update Notification',
        category: 'General',
        requiresRestart: false,
        default: true,"
    new="label: 'Enable Auto Update Notification',
        category: 'General',
        requiresRestart: false,
        default: false,"
    replace_if_present "$settings_schema" "$old" "$new"

    old="label: 'Hide Banner',
        category: 'UI',
        requiresRestart: false,
        default: false,"
    new="label: 'Hide Banner',
        category: 'UI',
        requiresRestart: false,
        default: true,"
    replace_if_present "$settings_schema" "$old" "$new"

    old="import { checkForUpdates } from './ui/utils/updateCheck.js';
import { handleAutoUpdate } from './utils/handleAutoUpdate.js';"
    replace_if_present "$interactive_cli" "$old" ""

    old="  debugLogger,
"
    replace_if_present "$interactive_cli" "$old" ""

    old="  checkForUpdates(settings)
    .then((info) => {
      handleAutoUpdate(info, settings, config.getProjectRoot());
    })
    .catch((err) => {
      // Silently ignore update check errors.
      if (config.getDebugMode()) {
        debugLogger.warn('Update check failed:', err);
      }
    });
"
    replace_if_present "$interactive_cli" "$old" ""

    old="const [bannerVisible, setBannerVisible] = useState(true);"
    new="const [bannerVisible, setBannerVisible] = useState(false);"
    replace_if_present "$app_container" "$old" "$new"

    old="        setBannerVisible(true);"
    replace_if_present "$app_container" "$old" ""

    old="        const isEsrch = err.code === 'ESRCH';
        const isWindowsPtyError = err.message?.includes(
          'Cannot resize a pty that has already exited',
        );

        if (isEsrch || isWindowsPtyError) {
          // On Unix, we get an ESRCH error.
          // On Windows, we get a message-based error.
          // In both cases, it's safe to ignore."
    new="        const isEsrch = err.code === 'ESRCH';
        const isEbadf =
          err.code === 'EBADF' || err.message?.includes('EBADF');
        const isWindowsPtyError = err.message?.includes(
          'Cannot resize a pty that has already exited',
        );

        if (isEsrch || isEbadf || isWindowsPtyError) {
          // On Unix, we get an ESRCH error.
          // Some PTY backends surface EBADF only via the message text.
          // On Windows, we get a message-based error.
          // In both cases, it's safe to ignore."
    replace_if_present "$shell_service" "$old" "$new"

    old="    it('should re-throw other errors during resize', async () => {"
    new="    it('should ignore EBADF resize errors surfaced via the error message', () => {
      const resizeError = new Error('ioctl(2) failed, EBADF');
      mockPtyProcess.resize.mockImplementation(() => {
        throw resizeError;
      });

      expect(() => {
        ShellExecutionService.resizePty(mockPtyProcess.pid, 100, 40);
      }).not.toThrow();

      expect(mockPtyProcess.resize).toHaveBeenCalledWith(100, 40);
      expect(mockHeadlessTerminal.resize).not.toHaveBeenCalled();
    });

    it('should re-throw other errors during resize', async () => {"
    replace_if_present "$shell_service_test" "$old" "$new"

    old="export const DEFAULT_CORE_POLICIES_DIR = path.join(__dirname, 'policies');"
    new="const envObj = process.env; export const DEFAULT_CORE_POLICIES_DIR = envObj['GEMINI_POLICIES_DIR'] || path.join(__dirname, 'policies');"
    replace_if_present "$core_policy_config" "$old" "$new"

    old='export const DEFAULT_CORE_POLICIES_DIR = path.join(__dirname, "policies");'
    new='const envObj = process.env; export const DEFAULT_CORE_POLICIES_DIR = envObj["GEMINI_POLICIES_DIR"] || path.join(__dirname, "policies");'
    replace_if_present "$core_policy_config" "$old" "$new"
    perl -0pi -e 's/path\.(join|resolve)\(__dirname,\s*(["'\''''])(?:\.\.\/)?policies\/?\2?,\s*(["'\''''])sandbox-default\.toml\3\)/path.$1(DEFAULT_CORE_POLICIES_DIR, "sandbox-default.toml")/g' "$core_policy_config"
    perl -0pi -e 's/path\.(join|resolve)\(__dirname,\s*(["'\''''])(?:\.\.\/)?policies\/?sandbox-default\.toml\2\)/path.$1(DEFAULT_CORE_POLICIES_DIR, "sandbox-default.toml")/g' "$core_policy_config"
  '';

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

    inherit npmDepsHash;

    npmDepsFetcherVersion = 2;

    nativeBuildInputs = [ bash bun makeWrapper perl ];

    npmBuildScript = "bundle";
    npmFlags = [ "--ignore-scripts" ];

    postPatch = ''
      ${lib.getExe bash} ${applyDownstreamPatches} "$PWD"
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/share/${manifest.package.repo}/bundle"

      bun build --compile --bytecode --format=esm bundle/gemini.js \
        --outfile "$out/bin/${manifest.binary.name}"

      cp -rL bundle/. "$out/share/${manifest.package.repo}/bundle/"

      wrapProgram "$out/bin/${manifest.binary.name}" \
        --set GEMINI_CLI_NO_RELAUNCH "true" \
        --set GEMINI_POLICIES_DIR "$out/share/${manifest.package.repo}/bundle/policies" \
        --set NODE_PATH "$out/share/${manifest.package.repo}/bundle/node_modules"

      runHook postInstall
    '';

    meta = with lib; {
      description = manifest.meta.description;
      homepage = manifest.meta.homepage;
      license = resolvedLicense;
      mainProgram = manifest.binary.name;
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