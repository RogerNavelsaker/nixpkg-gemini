#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fake_hash='sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='

set_hash_for_attr() {
  local attr="$1"
  local value="$2"

  python3 - "$attr" "$value" "$repo_root/flake.nix" <<'PY'
import pathlib
import re
import sys

attr = sys.argv[1]
value = sys.argv[2]
flake_path = pathlib.Path(sys.argv[3])
text = flake_path.read_text()

attr_names = {
    "stable": ["default", "stable"],
    "main": ["main"],
    "nightly": ["nightly"],
}[attr]

for name in attr_names:
    pattern = re.compile(
        rf'({name}\s*=\s*pkgs\.callPackage \./nix/package\.nix \{{.*?npmDepsHash = ")([^"]+)(";)'
        ,
        re.S,
    )
    text, count = pattern.subn(rf'\g<1>{value}\g<3>', text, count=1)
    if count != 1:
        raise SystemExit(f"failed to update npmDepsHash for {name}")

flake_path.write_text(text)
PY
}

extract_hash_from_log() {
  local log_path="$1"

  python3 - "$log_path" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
matches = re.findall(r'got:\s+(sha256-[A-Za-z0-9+/=]+)', text)
if matches:
    print(matches[-1])
PY
}

refresh_hash_for_attr() {
  local attr="$1"
  local log_file

  set_hash_for_attr "$attr" "$fake_hash"
  log_file="$(mktemp)"

  if nix --accept-flake-config build ".#${attr}" --no-link > /dev/null 2> "$log_file"; then
    echo "expected an npmDepsHash mismatch while probing ${attr}" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  local actual_hash
  actual_hash="$(extract_hash_from_log "$log_file")"
  rm -f "$log_file"

  if [[ -z "$actual_hash" ]]; then
    echo "failed to extract npmDepsHash for ${attr}" >&2
    exit 1
  fi

  set_hash_for_attr "$attr" "$actual_hash"
}

bun run sync:github-source

nix --accept-flake-config flake update \
  gemini-cli-main-src \
  gemini-cli-nightly-src \
  gemini-cli-stable-src

refresh_hash_for_attr stable
refresh_hash_for_attr main
refresh_hash_for_attr nightly

nix --accept-flake-config build .#stable --no-link
nix --accept-flake-config build .#main --no-link
nix --accept-flake-config build .#nightly --no-link
