# gemini-cli

Nix packaging for `@google/gemini-cli` using Bun and `bun2nix`.

## Package

- Upstream package: `@google/gemini-cli`
- Pinned version: `0.34.0`
- Installed binary: `gemini`
- Upstream executable invoked by Bun: `gemini`

## What this repo does

- Uses `bun.lock` and generated `bun.nix` as the dependency lock surface for Nix
- Builds an internal Bun application package with `bun2nix`
- Exposes only the canonical binary name `gemini`
- Applies Gemini-specific package-time patches for the EBADF PTY crash and aggressive retry behavior
- Provides a GitHub Actions workflow that can sync the pinned npm version

## Files

- `flake.nix`: flake entrypoint
- `nix/package.nix`: Nix derivation, including Gemini-only runtime patches
- `nix/package-manifest.json`: pinned package metadata and exposed binary name
- `scripts/sync-from-npm.ts`: updates pinned npm metadata without changing the canonical output binary

## Usage

```bash
nix build
./result/bin/gemini --help
```

## Notes

- This package does not set `TERM` for you.
- If you want wrapper-level `TERM` behavior or local aliases such as `gmi`, set those outside this repo.
