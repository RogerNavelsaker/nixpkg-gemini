{
  bash,
  bun,
  bun2nix,
  gemini-cli-src,
  lib,
  makeWrapper,
  perl,
  runCommand,
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
    new="const [bannerVisible] = useState(false);"
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
  cleanPackagingSource = builtins.path {
    name = "gemini-cli-packaging-src";
    path = ../.;
  };
  sourceTree = runCommand "gemini-cli-packaging-source" { nativeBuildInputs = [ perl ]; } ''
    mkdir -p "$out"
    cp -a ${cleanPackagingSource}/. "$out/"
    chmod -R u+w "$out"
    mkdir -p "$out/vendor"
    cp -a ${gemini-cli-src}/. "$out/vendor/gemini-cli"
    ${lib.getExe bash} ${applyDownstreamPatches} "$out/vendor/gemini-cli"
  '';
  basePackage = bun2nix.writeBunApplication {
    pname = manifest.package.repo;
    version = packageVersion;
    packageJson = "${sourceTree}/package.json";
    src = sourceTree;
    dontUseBunBuild = true;
    dontUseBunCheck = true;
    startScript = ''
      bunx ${manifest.package.repo} "$@"
    '';
    bunDeps = bun2nix.fetchBunDeps {
      bunNix = "${sourceTree}/bun.nix";
    };
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
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    rm -rf "$out/bin"
    mkdir -p "$out/bin"
    entrypoint="$(find "${basePackage}/share/${manifest.package.repo}/node_modules" -path "*/node_modules/${manifest.package.npmName}/${manifest.binary.entrypoint}" | head -n 1)"
    cat > "$out/bin/${manifest.binary.name}" <<EOF
#!${lib.getExe bash}
export GEMINI_FORCE_FILE_STORAGE=true
exec ${lib.getExe' bun "bun"} "$entrypoint" "\$@"
EOF
    chmod +x "$out/bin/${manifest.binary.name}"
    ${aliasOutputLinks}
  '';
  meta = basePackage.meta;
}
