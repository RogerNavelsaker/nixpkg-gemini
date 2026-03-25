# nixpkg-gemini

Nix packaging for the forked `RogerNavelsaker/gemini-cli` source repo.

## Package

- Source repo: `RogerNavelsaker/gemini-cli`
- Pinned version: `0.35.0`
- Installed binary: `gemini`
- Alias output: `gmi --yolo`

## What This Repo Does

- Fetches the forked Gemini CLI source as a flake input
- Builds the fork with `buildNpmPackage`
- Wraps the packaged CLI with `GEMINI_FORCE_FILE_STORAGE=true`
- Exposes only packaging concerns in this repo

## Files

- `flake.nix`: flake entrypoint and source input pin
- `nix/package.nix`: packaging-only derivation and wrapper outputs
- `nix/package-manifest.json`: binary metadata and package version

## Notes

- Runtime behavior patches live in `RogerNavelsaker/gemini-cli`, not here.
- The default `out` output installs the longform binary name `gemini`.
- The shortform wrapper `gmi --yolo` is available as a separate Nix output, not in the default `out` output.
