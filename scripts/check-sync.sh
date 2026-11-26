#!/usr/bin/env bash
# Repo-local sync checks. Exit non-zero on any FAIL. One PASS/FAIL/SKIP line per check.
# Env: CHECK_OFFLINE=1 skips network checks; BASE_REF=<ref> enables the bump-on-change check.
set -uo pipefail

# ---- repo-specific config (edit only this block when copying to other nixpkg-* repos) ----
UPSTREAM_GIT_URL="https://github.com/google-gemini/gemini-cli.git"  # git ls-remote source
UPSTREAM_TAG_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+$'                      # stable tags only
UPSTREAM_TAG_PREFIX="v"                                             # stripped to get the manifest version
MANIFEST="nix/package-manifest.json"
MANIFEST_VERSION_JQ='.package.version'
PINNED_PATHS=(vendor bun.lock)                                      # paths whose change requires a version bump
PINNED_FLAKE_REGEX='github:google-gemini/gemini-cli|npmDepsHash|Hashes' # flake.nix diff lines that count as a source pin change
CACHIX_NAME="rogernavelsaker"
SYNC_WORKFLOW=".github/workflows/sync-upstream.yml"
# ---- end config ----

cd "$(git rev-parse --show-toplevel)" || exit 2
fail=0
pass() { echo "PASS  $1"; }
skip() { echo "SKIP  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else bad "$name"; fi; }

WORKFLOWS=$(ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null)

no_path_inputs() {
  ! grep -nE '(url|path)[[:space:]]*=[[:space:]]*"path:|inputs\.[A-Za-z0-9_-]+\.url[[:space:]]*=[[:space:]]*"path:' flake.nix &&
  ! { [ -f flake.lock ] && jq -e '[.nodes[]?.locked.type? // empty] | any(. == "path")' flake.lock; }
}
no_local_sync() {
  # cp/rsync/ln of sibling folders (../ or /workspace) inside sync scripts or workflows
  ! grep -nE '(^|[[:space:];&|])(cp|rsync|ln|mv)[[:space:]].*(\.\./|/workspace/)' scripts/* $WORKFLOWS 2>/dev/null |
    grep -v '^scripts/check-sync.sh'
}
sync_schedule() { grep -qE '^[[:space:]]*schedule:' "$SYNC_WORKFLOW" && grep -qE '^[[:space:]]*-[[:space:]]*cron:' "$SYNC_WORKFLOW"; }
sync_commits() {
  grep -q 'git-auto-commit-action' "$SYNC_WORKFLOW" || grep -q 'git push' "$SYNC_WORKFLOW" || return 1
  ! grep -qE '^[[:space:]]*branch:' "$SYNC_WORKFLOW" # default branch = no explicit target branch
}
cachix_workflow() { grep -q 'cachix/cachix-action' $WORKFLOWS && grep -qE "name:[[:space:]]*\"?$CACHIX_NAME\"?[[:space:]]*$" $WORKFLOWS; }
cachix_flake() { grep -q "https://$CACHIX_NAME.cachix.org" flake.nix; }
no_npm_publish() {
  ! grep -rnE 'npm publish|NPM_TOKEN' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.devenv \
      --exclude=check-sync.sh --exclude='result*' . 2>/dev/null
}

check "no path: flake inputs (flake.nix, flake.lock)" no_path_inputs
check "no local folder-to-folder sync (scripts, workflows)" no_local_sync
check "sync workflow has schedule cron" sync_schedule
check "sync workflow commits to default branch" sync_commits
check "cachix-action configured (name $CACHIX_NAME)" cachix_workflow
check "flake nixConfig has $CACHIX_NAME substituter" cachix_flake
check "no npm publish / NPM_TOKEN" no_npm_publish

manifest_version=$(jq -r "$MANIFEST_VERSION_JQ" "$MANIFEST" 2>/dev/null)
if [ -z "$manifest_version" ] || [ "$manifest_version" = null ]; then
  bad "manifest version readable ($MANIFEST)"
fi

# VERSION BUMP: manifest equals latest upstream
if [ "${CHECK_OFFLINE:-0}" = 1 ]; then
  skip "manifest version == latest upstream (CHECK_OFFLINE=1)"
else
  if tags=$(git ls-remote --tags --refs "$UPSTREAM_GIT_URL" 2>/dev/null) && [ -n "$tags" ]; then
    latest=$(printf '%s\n' "$tags" | awk '{sub("refs/tags/","",$2); print $2}' | grep -E "$UPSTREAM_TAG_REGEX" | sort -V | tail -n1)
    latest=${latest#"$UPSTREAM_TAG_PREFIX"}
    if [ -z "$latest" ]; then bad "manifest version == latest upstream (no matching upstream tag)"
    elif [ "$manifest_version" = "$latest" ]; then pass "manifest version == latest upstream ($latest)"
    else bad "manifest version $manifest_version != latest upstream $latest"; fi
  else
    bad "manifest version == latest upstream (git ls-remote failed; set CHECK_OFFLINE=1 to skip)"
  fi
fi

# VERSION BUMP ON CHANGE
if [ -z "${BASE_REF:-}" ]; then
  skip "version bump on pinned-source change (BASE_REF unset)"
elif ! git rev-parse --verify -q "$BASE_REF^{commit}" >/dev/null; then
  bad "version bump on pinned-source change (BASE_REF $BASE_REF not found; use fetch-depth 0)"
else
  base=$(git merge-base "$BASE_REF" HEAD 2>/dev/null || git rev-parse "$BASE_REF")
  changed=""
  [ -n "$(git diff --name-only "$base" -- "${PINNED_PATHS[@]}")" ] && changed="${PINNED_PATHS[*]}"
  if [ -z "$changed" ] && git diff -U0 "$base" -- flake.nix | grep -E '^[+-][^+-]' | grep -qE "$PINNED_FLAKE_REGEX"; then
    changed="flake.nix pins"
  fi
  if [ -z "$changed" ] && git diff -U0 "$base" -- "$MANIFEST" | grep -E '^[+-][^+-]' | grep -vE '"version"' | grep -qE '(rev|hash|sha|tag)'; then
    changed="$MANIFEST source rev/hash"
  fi
  if [ -z "$changed" ]; then
    pass "version bump on pinned-source change (no pinned source change vs $BASE_REF)"
  else
    base_version=$(git show "$base:$MANIFEST" 2>/dev/null | jq -r "$MANIFEST_VERSION_JQ")
    if [ "$manifest_version" != "$base_version" ]; then pass "version bump on pinned-source change ($base_version -> $manifest_version; changed: $changed)"
    else bad "pinned source changed ($changed) but manifest version still $base_version"; fi
  fi
fi

exit $fail
