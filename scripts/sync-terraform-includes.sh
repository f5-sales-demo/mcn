#!/usr/bin/env bash
# Mirror the deployment's Terraform into docs/_includes/terraform/ so the
# documentation can show the real configuration instead of a retyped copy.
#
# Why a copy exists at all: the documentation site is built in a container with
# only docs/ mounted, so nothing under terraform/ is reachable at render time. The
# pages import these files with Vite's `?raw`, which means the configuration never
# appears as text in any .mdx — and therefore is never fed to the translator, which
# would otherwise translate the comments inside it and publish a different
# configuration for every locale.
#
# A copy is a lie waiting to happen, so --check fails CI the moment the copy and
# the source diverge. Run without --check to bring the copy back in line.
#
# ⚠️ THIS SCRIPT SHOULD NOT EXIST, and is expected to be deleted.
# docs/_imports is the ecosystem's mechanism for publishing repository files in
# documentation, and it already stages 33 captured outputs for this repo. It cannot
# express a directory TREE, because the deploy workflow stages every entry onto its
# basename — so mcn's four main.tf, four variables.tf and four versions.tf would
# silently collapse onto each other and pages would render the wrong file. That is
# docs-control#849, which proposes an opt-in `source -> dest` form. When it lands,
# list terraform/**/*.tf in docs/_imports, point the pages at _data/, and delete
# this script, tests/test-terraform-includes.sh and docs/_includes/ entirely.
#
#   scripts/sync-terraform-includes.sh            # sync
#   scripts/sync-terraform-includes.sh --check    # verify only, non-zero on drift
#
# Only *.tf is copied. terraform.tfvars is deliberately excluded and must never be
# published: it holds per-engineer values and a subscription id.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
  --root)
    ROOT=$(cd "$2" && pwd)
    shift 2
    ;;
  --check)
    CHECK=1
    shift
    ;;
  -h | --help)
    sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

SRC="${ROOT}/terraform"
DEST="${ROOT}/docs/_includes/terraform"

if [ ! -d "$SRC" ]; then
  echo "no terraform/ directory under ${ROOT}" >&2
  exit 2
fi

# Relative paths of every .tf under terraform/, sorted for deterministic output.
# A read loop rather than `mapfile`, which does not exist in bash 3.2 — the version
# macOS ships, and therefore the version this runs under locally even though CI has
# bash 5. Terraform file names cannot contain newlines in practice, and a repo that
# managed one would fail `terraform fmt` long before reaching this script.
TF_FILES=()
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  TF_FILES+=("$rel")
done < <(cd "$SRC" && find . -name '*.tf' -type f | sed 's|^\./||' | sort)

DRIFT=0
note() {
  if [ "$CHECK" -eq 1 ]; then
    echo "$1"
  fi
}

for rel in "${TF_FILES[@]}"; do
  src="${SRC}/${rel}"
  dst="${DEST}/${rel}"
  if [ ! -f "$dst" ]; then
    note "missing from docs/_includes/terraform: ${rel}"
    DRIFT=1
    if [ "$CHECK" -eq 0 ]; then
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
    fi
  elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
    note "out of date in docs/_includes/terraform: ${rel}"
    DRIFT=1
    if [ "$CHECK" -eq 0 ]; then
      cp "$src" "$dst"
    fi
  fi
done

# Orphans: a copy whose source was deleted or renamed. Left alone it would publish
# configuration this deployment no longer has, which is worse than showing none.
if [ -d "$DEST" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -f "${SRC}/${rel}" ]; then
      note "orphaned in docs/_includes/terraform (source is gone): ${rel}"
      DRIFT=1
      if [ "$CHECK" -eq 0 ]; then
        rm -f "${DEST}/${rel}"
      fi
    fi
  done < <(cd "$DEST" && find . -name '*.tf' -type f | sed 's|^\./||' | sort)

  # Prune directories left empty by an orphan removal, so the tree mirrors
  # terraform/ exactly and a deleted module leaves nothing behind.
  if [ "$CHECK" -eq 0 ]; then
    find "$DEST" -mindepth 1 -type d -empty -delete
  fi
fi

if [ "$CHECK" -eq 1 ]; then
  if [ "$DRIFT" -eq 1 ]; then
    echo "FAIL: docs/_includes/terraform is out of sync with terraform/." >&2
    echo "Run scripts/sync-terraform-includes.sh and commit the result." >&2
    exit 1
  fi
  echo "PASS: docs/_includes/terraform matches terraform/ (${#TF_FILES[@]} files)."
  exit 0
fi

echo "Synced ${#TF_FILES[@]} Terraform files into docs/_includes/terraform/."
