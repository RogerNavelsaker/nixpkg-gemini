# nixpkg-gemini

Nix packaging for the prepared `RogerNavelsaker/gemini-cli` package repo.

## Package

- Source repo: `RogerNavelsaker/gemini-cli`
- Pinned version: `0.35.0`
- Installed binary: `gemini`
- Alias output: `gmi --yolo`

## What This Repo Does

- Vendors the prepared package repo as a local Bun dependency
- Resolves the upstream npm package graph through `bun.lock` and `bun.nix`
- Wraps the final CLI with `GEMINI_FORCE_FILE_STORAGE=true`
- Keeps runtime patching out of this repo

## Files

- `flake.nix`: flake entrypoint and prep repo input pin
- `nix/package.nix`: Bun wrapper derivation and final binary outputs
- `nix/package-manifest.json`: binary metadata and package version

## Notes

- Runtime behavior patches live in `RogerNavelsaker/gemini-cli`, not here.
- The default `out` output installs the longform binary name `gemini`.
- The shortform wrapper `gmi --yolo` is available as a separate Nix output, not in the default `out` output.
