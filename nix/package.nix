{
  bash,
  buildNpmPackage,
  bun,
  gemini-cli-src,
  git,
  lib,
  makeWrapper,
  npmDepsHash,
  perl,
  runCommand,
  stdenv,
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
  bunCompileTarget =
    {
      "x86_64-linux" = "bun-linux-x64";
      "aarch64-linux" = "bun-linux-arm64";
      "x86_64-darwin" = "bun-darwin-x64";
      "aarch64-darwin" = "bun-darwin-arm64";
    }.${stdenv.hostPlatform.system}
      or (throw "unsupported Bun compile target for ${stdenv.hostPlatform.system}");
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
  cleanPackagingSource = builtins.path {
    name = "gemini-cli-packaging-src";
    path = ../.;
  };
  sourceTree = runCommand "gemini-cli-packaging-source" { nativeBuildInputs = [ perl ]; } ''
    staging="$(mktemp -d)"
    cp -a ${cleanPackagingSource}/. "$staging/"
    chmod -R u+w "$staging"
    mkdir -p "$staging/vendor"
    cp -a ${gemini-cli-src}/. "$staging/vendor/gemini-cli"
    chmod -R u+w "$staging/vendor/gemini-cli"
    ${lib.getExe bash} ${applyDownstreamPatches} "$staging/vendor/gemini-cli"
    mkdir -p "$out"
    cp -a "$staging"/. "$out/"
  '';
  basePackage = buildNpmPackage {
    pname = manifest.package.repo;
    version = packageVersion;
    src = "${sourceTree}/vendor/gemini-cli";
    inherit npmDepsHash;
    npmDepsFetcherVersion = 2;
    npmInstallFlags = [ "--omit=optional" ];
    npmBuildScript = "bundle";
    nativeBuildInputs = [ bun git makeWrapper ];
    installPhase = ''
      runHook preInstall
      
      # Strip max-old-space-size to prevent Bun from passing it as a positional argument
      perl -pi -e 's/--(max-old-space-size|maxOldSpaceSize)[= ]?[0-9]*//g' bundle/gemini.js || true

      # Patch policies fallback directly in the bundle to guarantee runtime resolution
      perl -pi -e 's/(path\.join\(__dirname,\s*(["\x27])(?:\/)?policies\2\))/(process.env.GEMINI_POLICIES_DIR ?? $1)/g' bundle/gemini.js || true

      mkdir -p "$out/bin" "$out/share/${manifest.package.repo}"
      cp -rL bundle "$out/share/${manifest.package.repo}/bundle"
      ${lib.getExe' bun "bun"} build \
        --compile \
        --target=${bunCompileTarget} \
        --format=esm \
        --bytecode \
        --minify \
        --production \
        --external=keytar \
        --external=@github/keytar \
        --outfile "$out/share/${manifest.package.repo}/${manifest.binary.name}" \
        bundle/gemini.js
      wrapProgram "$out/share/${manifest.package.repo}/${manifest.binary.name}" \
        --set GEMINI_CLI_NO_RELAUNCH "true" \
        --set GEMINI_POLICIES_DIR "$out/share/${manifest.package.repo}/bundle/policies"
      ln -s "$out/share/${manifest.package.repo}/${manifest.binary.name}" "$out/bin/${manifest.binary.name}"
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
