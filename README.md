# nixpkg-gemini

Nix packaging for the forked `@google/gemini-cli` using Bun and `bun2nix`.

## Package

- Source repo: `RogerNavelsaker/gemini-cli`
- Pinned version: `0.35.0`
- Installed binary: `gemini`
- Alias output: `gmi --yolo`

## What This Repo Does

- Uses `bun.lock` and generated `bun.nix` as the dependency lock surface for Nix
- Builds the forked package as an internal Bun application with `bun2nix`
- Wraps the CLI with `GEMINI_FORCE_FILE_STORAGE=true`
- Keeps runtime behavior patches in `RogerNavelsaker/gemini-cli`, not here

## Files

- `flake.nix`: flake entrypoint
- `nix/package.nix`: Bun-wrapped derivation and wrapper outputs
- `nix/package-manifest.json`: binary metadata and package version

## Notes

- Runtime behavior patches live in `RogerNavelsaker/gemini-cli`, not here.
- The default `out` output installs the longform binary name `gemini`.
- The shortform wrapper `gmi --yolo` is available as a separate Nix output, not in the default `out` output.
