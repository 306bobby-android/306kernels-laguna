#!/usr/bin/env bash
# Shared paths/helpers. Source this; do not run it.
# WORKSPACE defaults to the GitHub workspace so the same scripts run locally.

WORKSPACE="${WORKSPACE:-${GITHUB_WORKSPACE:-$PWD}}"
KERNEL_ROOT="${KERNEL_ROOT:-$WORKSPACE/kernel}"
# shellcheck disable=SC2034  # used by the scripts that source this file
COMMON="$KERNEL_ROOT/common"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

log()  { printf '[*] %s\n' "$*"; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Export to later workflow steps when running under Actions, and to this shell.
setenv() {
  local k="$1" v="$2"
  export "$k=$v"
  if [ -n "${GITHUB_ENV:-}" ]; then printf '%s=%s\n' "$k" "$v" >> "$GITHUB_ENV"; fi
}

retry() {
  local n=0
  until [ "$n" -ge 5 ]; do
    "$@" && return 0
    n=$((n + 1))
    warn "retry $n/5 failed for: $*"
    sleep 5
  done
  return 1
}

require_sha() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]] || die "expected a 40-char sha, got '$1'"
}

# Resolve a ref (branch, tag or sha) on a remote to a full sha.
resolve_ref() {
  local url="$1" ref="$2" sha
  if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then echo "$ref"; return 0; fi
  sha="$(git ls-remote "$url" "refs/heads/$ref" "refs/tags/$ref" | head -n1 | cut -f1)"
  [ -n "$sha" ] || die "could not resolve '$ref' on $url"
  echo "$sha"
}
