# gemini-cli

Nix packaging for `@google/gemini-cli` using Bun and `bun2nix`.

## Package

- Upstream package: `@google/gemini-cli`
- Pinned version: `0.34.0`
- Installed binary: `gemini`
- Upstream executable invoked by Bun: `gemini`

## What This Repo Does

- Uses `bun.lock` and generated `bun.nix` as the dependency lock surface for Nix
- Builds the upstream package as an internal Bun application with `bun2nix`
- Exposes only the canonical binary name `gemini`
- Applies Gemini-specific package-time patches for the EBADF PTY crash and aggressive retry behavior
- Provides a manifest sync script for updating the pinned npm metadata

## Files

- `flake.nix`: flake entrypoint
- `nix/package.nix`: Nix derivation, including Gemini-only runtime patches
- `nix/package-manifest.json`: pinned package metadata and exposed binary name
- `scripts/sync-from-npm.ts`: updates pinned npm metadata without changing the canonical output binary

## Notes

- The default `out` output installs the longform binary name `gemini`.
- The shortform wrapper `gmi --yolo` is available as a separate Nix output, not in the default `out` output.
- This repo also does not set `TERM` for you.
