#!/usr/bin/env bash
# Repository-specific pre-commit checks, invoked by the `local-hooks` hook in
# .pre-commit-config.yaml (which is governance-managed and must not be edited
# here — this file is the sanctioned extension point).
#
# Everything below is offline and credential-free, so it behaves identically on a
# workstation and in CI. Refreshing the CE command catalog is deliberately NOT
# here: it needs a live tenant, and no runner can hold that credential. See
# scripts/capture-sitecli.sh.
set -euo pipefail

cd "$(dirname "$0")/.."

run() {
  printf '\n== %s\n' "$1"
  shift
  "$@"
}

# The hook is wired with `always_run: true` and `pass_filenames: false`, so the
# relevance check has to happen here. The CE suite takes ~12s; running it on a
# commit that touches only Terraform earns nothing and is how hooks end up
# disabled. `git diff` against HEAD covers the staged set; when there is no HEAD
# yet (initial commit) fall back to running everything.
staged() {
  if git rev-parse --verify -q HEAD >/dev/null; then
    git diff --cached --name-only
  else
    git ls-files
  fi
}

if staged | grep -qE '^(sitecli/|scripts/(capture-sitecli|check-sitecli-docs|sitecli-scrub|pre-commit-local)\.sh|tests/test-(sitecli-scrub|check-sitecli-docs)\.sh|docs/(_imports|en/customer-edge/))'; then
  run "CE scrub filter tests"           bash tests/test-sitecli-scrub.sh
  run "CE docs consistency gate tests"  bash tests/test-check-sitecli-docs.sh
  run "CE catalog vs documentation"     bash scripts/check-sitecli-docs.sh
else
  printf 'CE Site CLI checks skipped (no related paths staged)\n'
fi
