#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bun run scripts/sync-from-github.ts

nix --accept-flake-config flake update \
  gemini-cli-main-src \
  gemini-cli-nightly-src \
  gemini-cli-stable-src

compute_npm_hash() {
  local attr="$1"
  echo "Computing npmDepsHash for ${attr}..." >&2

  local rev
  rev=$(nix flake metadata --json | jq -r ".locks.nodes.\"gemini-cli-${attr}-src\".locked.rev")
  local src_path
  src_path=$(nix flake prefetch --json "github:google-gemini/gemini-cli/${rev}" | jq -r .storePath)

  # Use lib.fakeHash to trigger hash computation with npmDepsFetcherVersion = 2
  local fake="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
  sed -i "s|${attr} = \"sha256-[^\"]*\";|${attr} = \"${fake}\";|" flake.nix

  local hash
  hash=$(nix --accept-flake-config build ".#${attr}" --no-link 2>&1 | grep "got:" | grep -o "sha256-[^'\"[:space:]]*") || true

  if [[ -z "$hash" ]]; then
    echo "ERROR: failed to compute hash for ${attr}" >&2
    exit 1
  fi

  echo "$hash"
}

stable_hash=$(compute_npm_hash stable)
main_hash=$(compute_npm_hash main)
nightly_hash=$(compute_npm_hash nightly)

echo "stable:  $stable_hash"
echo "main:    $main_hash"
echo "nightly: $nightly_hash"

# Write final hashes into flake.nix
sed -i \
  -e "s|stable = \"sha256-[^\"]*\";|stable = \"${stable_hash}\";|" \
  -e "s|main   = \"sha256-[^\"]*\";|main   = \"${main_hash}\";|" \
  -e "s|nightly = \"sha256-[^\"]*\";|nightly = \"${nightly_hash}\";|" \
  flake.nix

nix --accept-flake-config build .#stable --no-link
nix --accept-flake-config build .#main --no-link
nix --accept-flake-config build .#nightly --no-link
