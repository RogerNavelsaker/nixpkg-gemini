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
  sed -i "s|${attr}[[:space:]]*= \"sha256-[^\"]*\";|${attr} = \"${fake}\";|" flake.nix

  local hash
  hash=$(nix --accept-flake-config build ".#${attr}" --no-link 2>&1 | grep -o "sha256-[a-zA-Z0-9+/=]\{43,\}" | grep -v "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" | tail -n 1) || true
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
  -e "s|stable[[:space:]]*= \"sha256-[^\"]*\";|stable = \"${stable_hash}\";|" \
  -e "s|main[[:space:]]*= \"sha256-[^\"]*\";|main = \"${main_hash}\";|" \
  -e "s|nightly[[:space:]]*= \"sha256-[^\"]*\";|nightly = \"${nightly_hash}\";|" \
  flake.nix

nix --accept-flake-config build .#stable --no-link
nix --accept-flake-config build .#main --no-link
nix --accept-flake-config build .#nightly --no-link

# Smoke test: bun --compile happily produces binaries with unresolved refs that
# crash at startup (e.g. v0.42.0 ReferenceError: checkForUpdates is not defined).
# Build success is necessary but not sufficient — exercise startInteractiveUI by
# running the binary briefly and assert no critical error.
smoke_test() {
  local attr="$1"
  local out
  out=$(nix --accept-flake-config build ".#${attr}" --print-out-paths --no-link 2>/dev/null | head -n 1)
  local bin="${out}/bin/gemini"
  [ -x "$bin" ] || { echo "smoke[$attr]: binary missing at $bin" >&2; return 1; }
  local log
  log=$(mktemp)
  # Run briefly under a fake TTY; timeout-kill is the expected exit.
  script -qfc "timeout 5 ${bin} --yolo --sandbox false" "$log" </dev/null >/dev/null 2>&1 || true
  if grep -qE "An unexpected critical error|ReferenceError|TypeError|ENOENT.*sandbox" "$log"; then
    echo "smoke[$attr]: FAILED — startup crash detected" >&2
    sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' "$log" | grep -E "Error|critical" | head -20 >&2
    return 1
  fi
  echo "smoke[$attr]: ok"
}

smoke_test stable
smoke_test main
smoke_test nightly
