# nixpkg-gemini

Nix packaging for `google-gemini/gemini-cli` with a downstream patch set applied in Nix.

## Package

- Source repo: `google-gemini/gemini-cli`
- Default pinned version: `v0.38.2`
- Installed binary: `gemini`
- Alias output: `gmi --yolo`

### Tracking Branches

Downstream flakes can choose to follow specific upstream refs:
- **Release (default):** Uses `google-gemini/gemini-cli@v0.38.2` and exposes `packages.default`.
- **Stable tag (`v0.38.2`):** Uses the `gemini-cli-stable-src` input and exposes `packages.stable`.
- **Main:** Uses `google-gemini/gemini-cli@main` and exposes `packages.main`.
- **Nightly:** Uses `google-gemini/gemini-cli@v0.40.0-nightly.20260415.g06e7621b2` and exposes `packages.nightly`.

To use a specific tracking target, refer to `packages.<system>.stable`, `packages.<system>.main`, or `packages.<system>.nightly` in your flake.

## What This Repo Does

- Vendors the upstream `packages/cli` source as a local Bun dependency
- Applies the downstream patch set during the Nix build
- Resolves the upstream package graph through `bun.lock` and `bun.nix`
- Wraps the final CLI with `GEMINI_FORCE_FILE_STORAGE=true`
- Keeps the downstream changes isolated to this packaging repo

## Files

- `flake.nix`: flake entrypoint and upstream source pins
- `nix/package.nix`: Bun wrapper derivation, vendoring, and downstream patch application
- `nix/package-manifest.json`: binary metadata and package version

## Notes

- Runtime behavior patches now live in this repo and are applied during the build.
- The default `out` output installs the longform binary name `gemini`.
- The shortform wrapper `gmi --yolo` is available as a separate Nix output, not in the default `out` output.
