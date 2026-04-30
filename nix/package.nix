{
  bash,
  bun,
  buildNpmPackage,
  gemini-cli-src,
  npmDepsHash,
  lib,
  makeWrapper,
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

    find "$1/packages/core/src" -name "*.ts" -type f -exec perl -0pi -e 's/path\.(join|resolve)\([^\)]*sandbox-default\.toml[^\)]*\)/path.join(process.env.GEMINI_POLICIES_DIR || path.join(__dirname, "policies"), "sandbox-default.toml")/g' {} +

    shell_tool_message="$1/packages/cli/src/ui/components/messages/ShellToolMessage.tsx"
    retry_utils="$1/packages/core/src/utils/retry.ts"
    error_classification="$1/packages/core/src/availability/errorClassification.ts"

    old="if (!(e instanceof Error && e.message.includes('Cannot resize a pty that has already exited'))) {"
    new="if (!(e instanceof Error && (e.message.includes('Cannot resize a pty that has already exited') || e.message.includes('EBADF') || e.code === 'EBADF' || e.code === 'ESRCH'))) {"
    replace_if_present "$shell_tool_message" "$old" "$new"

    old="export const DEFAULT_MAX_ATTEMPTS = 10;"
    new="export const DEFAULT_MAX_ATTEMPTS = 1000;"
    replace_if_present "$retry_utils" "$old" "$new"

    old="initialDelayMs: 5000,"
    new="initialDelayMs: 1000,"
    replace_if_present "$retry_utils" "$old" "$new"

    old="maxDelayMs: 30000,"
    new="maxDelayMs: 5000,"
    replace_if_present "$retry_utils" "$old" "$new"

    old="if (error instanceof TerminalQuotaError) {
    return 'terminal';
  }"
    new="if (error instanceof TerminalQuotaError) {
    return 'retryable';
  }"
    replace_if_present "$error_classification" "$old" "$new"

    old="default: 10,
  description:
    'Maximum number of attempts for requests to the main chat model. Cannot exceed 10.',"
    new="default: 1000,
  description:
    'Maximum number of attempts for requests to the main chat model. Cannot exceed 1000.',"
    replace_if_present "$settings_schema" "$old" "$new"
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

    outputs = [ "out" "policies" ];

    npmDepsFetcherVersion = 2;

    nativeBuildInputs = [ bash bun makeWrapper perl ];

    npmBuildScript = "bundle";
    npmFlags = [ "--ignore-scripts" ];

    postPatch = ''
      ${lib.getExe bash} ${applyDownstreamPatches} "$PWD"
    '';

    preBuild = ''
      # Native PTY Resize Fix: belt-and-suspenders catch for EBADF in node-pty
      find node_modules -name "unixTerminal.js" -exec perl -0pi -e 's/pty\.resize\(this\._fd, cols, rows\);/try { pty.resize(this._fd, cols, rows); } catch (e) { if (e && (e.message?.includes("EBADF") || e.message?.includes("ESRCH") || e.code === "EBADF" || e.code === "ESRCH")) { return; } throw e; }/g' {} +
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/share/${manifest.package.repo}/bundle"
      mkdir -p "$policies/share/gemini-cli/policies"

      bun build --compile --bytecode --format=esm bundle/gemini.js \
        --outfile "$out/bin/${manifest.binary.name}"

      cp -rL bundle/. "$out/share/${manifest.package.repo}/bundle/"
      cp -rL bundle/policies/. "$policies/share/gemini-cli/policies/"

      # Remove duplicate policies and node_modules from out output
      # Since we are using bun --compile, we don't need node_modules at runtime
      rm -rf "$out/share/${manifest.package.repo}/bundle/policies"
      rm -rf "$out/share/${manifest.package.repo}/bundle/node_modules"

      # Create a node -> bun symlink in the libexec output to support any internal node calls
      mkdir -p "$out/libexec/bin"
      ln -s "${lib.getExe bun}" "$out/libexec/bin/node"

      wrapProgram "$out/bin/${manifest.binary.name}" \
        --set GEMINI_CLI_NO_RELAUNCH "true" \
        --set GEMINI_POLICIES_DIR "$policies/share/gemini-cli/policies" \
        --prefix PATH : "$out/libexec/bin"

      runHook postInstall
    '';

    preFixup = ''
      # Closure Pruning: remove unnecessary source files and build artifacts
      find "$out/share/${manifest.package.repo}/bundle" -name "*.ts" -type f -delete
      find "$out/share/${manifest.package.repo}/bundle" -name "*.map" -type f -delete
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
  outputs = [ "out" "policies" ] ++ map (alias: alias.name) aliasSpecs;
  paths = [ basePackage basePackage.policies ];
  postBuild = ''
    mkdir -p "$policies"
    cp -rL "${basePackage.policies}/." "$policies/"
    ${aliasOutputLinks}
  '';
  meta = basePackage.meta;
}
