#!/usr/bin/env bash
# Hermetic test for scripts/sync-terraform-includes.sh — the gate that keeps the
# Terraform shown in the documentation identical to the Terraform that deploys.
#
# The docs build mounts only docs/, so the configuration cannot be read from
# terraform/ at render time; a synced copy under docs/_includes/terraform/ is what
# the pages import. A copy is a lie waiting to happen, so --check exists to fail
# CI the moment the two diverge, and this test proves --check actually fails
# rather than merely passing when everything is already fine.
#
# Builds throwaway trees under a temporary directory and points the script at each
# with --root, so it never touches the repository it lives in and needs no network.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="${REPO_ROOT}/scripts/sync-terraform-includes.sh"

FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ok() { printf '  ok   — %s\n' "$1"; }
bad() {
  printf '  FAIL — %s\n' "$1"
  FAIL=1
}

# new_tree <name> — a minimal repo shape: two .tf files, one module .tf, plus the
# files that must NEVER be copied (tfvars carries per-engineer values and could
# carry a subscription id; .terraform.lock.hcl is a local artifact).
new_tree() {
  local root="${WORK}/$1"
  mkdir -p "${root}/terraform/modules/thing" "${root}/docs/en"
  printf 'variable "a" {\n  default = 1\n}\n' >"${root}/terraform/variables.tf"
  printf 'locals {\n  b = 2\n}\n' >"${root}/terraform/locals.tf"
  printf 'output "c" {\n  value = 3\n}\n' >"${root}/terraform/modules/thing/main.tf"
  printf 'subscription_id = "00000000-0000-0000-0000-000000000000"\n' >"${root}/terraform/terraform.tfvars"
  printf '# lock\n' >"${root}/terraform/.terraform.lock.hcl"
  echo "$root"
}

echo "1. sync copies every .tf and nothing else"
ROOT=$(new_tree sync)
if bash "$SCRIPT" --root "$ROOT" >/dev/null 2>&1; then
  for f in variables.tf locals.tf modules/thing/main.tf; do
    if [ -f "${ROOT}/docs/_includes/terraform/${f}" ] &&
      diff -q "${ROOT}/terraform/${f}" "${ROOT}/docs/_includes/terraform/${f}" >/dev/null; then
      ok "copied ${f} byte-identical"
    else
      bad "did not copy ${f} identically"
    fi
  done
  # A tfvars in the published docs tree would leak per-engineer values onto a
  # public site, so this is the assertion that matters most in this file.
  if [ -e "${ROOT}/docs/_includes/terraform/terraform.tfvars" ]; then
    bad "copied terraform.tfvars — it must NEVER reach docs/"
  else
    ok "did not copy terraform.tfvars"
  fi
  if [ -e "${ROOT}/docs/_includes/terraform/.terraform.lock.hcl" ]; then
    bad "copied .terraform.lock.hcl — not a .tf file"
  else
    ok "did not copy .terraform.lock.hcl"
  fi
else
  bad "sync exited non-zero on a clean tree"
fi

echo "2. sync is idempotent"
BEFORE=$(cd "${ROOT}/docs/_includes/terraform" && find . -type f -exec shasum -a 256 {} \; | sort)
bash "$SCRIPT" --root "$ROOT" >/dev/null 2>&1
AFTER=$(cd "${ROOT}/docs/_includes/terraform" && find . -type f -exec shasum -a 256 {} \; | sort)
if [ "$BEFORE" = "$AFTER" ]; then
  ok "second run produced an identical tree"
else
  bad "second run changed the tree"
fi

echo "3. --check passes immediately after a sync"
if bash "$SCRIPT" --root "$ROOT" --check >/dev/null 2>&1; then
  ok "--check exited 0 when in sync"
else
  bad "--check exited non-zero when in sync"
fi

echo "4. --check FAILS when a .tf is edited without re-syncing"
printf 'locals {\n  b = 99\n}\n' >"${ROOT}/terraform/locals.tf"
if bash "$SCRIPT" --root "$ROOT" --check >/dev/null 2>&1; then
  bad "--check passed while terraform/locals.tf differed from its copy"
else
  ok "--check caught the edited file"
fi

echo "5. --check FAILS when a new .tf is added without re-syncing"
ROOT2=$(new_tree added)
bash "$SCRIPT" --root "$ROOT2" >/dev/null 2>&1
printf 'variable "new" {\n  default = 0\n}\n' >"${ROOT2}/terraform/extra.tf"
if bash "$SCRIPT" --root "$ROOT2" --check >/dev/null 2>&1; then
  bad "--check passed while terraform/extra.tf had no copy"
else
  ok "--check caught the added file"
fi

echo "6. --check FAILS on a stale copy whose source was deleted, and sync prunes it"
ROOT3=$(new_tree stale)
bash "$SCRIPT" --root "$ROOT3" >/dev/null 2>&1
rm "${ROOT3}/terraform/locals.tf"
if bash "$SCRIPT" --root "$ROOT3" --check >/dev/null 2>&1; then
  bad "--check passed with an orphaned copy of a deleted source"
else
  ok "--check caught the orphaned copy"
fi
bash "$SCRIPT" --root "$ROOT3" >/dev/null 2>&1
if [ -e "${ROOT3}/docs/_includes/terraform/locals.tf" ]; then
  bad "sync left an orphaned copy behind"
else
  ok "sync pruned the orphaned copy"
fi

echo "7. --check reports which file diverged"
ROOT4=$(new_tree message)
bash "$SCRIPT" --root "$ROOT4" >/dev/null 2>&1
printf 'locals {\n  b = 7\n}\n' >"${ROOT4}/terraform/locals.tf"
OUT=$(bash "$SCRIPT" --root "$ROOT4" --check 2>&1 || true)
if printf '%s' "$OUT" | grep -q 'locals.tf'; then
  ok "named the diverged file in its output"
else
  bad "did not name the diverged file (output: ${OUT})"
fi

# The seven cases above are hermetic and prove the SCRIPT behaves. This last one is
# deliberately NOT hermetic: it runs --check against this repository. Without it CI
# would happily merge a Terraform edit whose published copy was never re-synced —
# the tests would pass on throwaway trees while the documentation showed stale
# configuration, which is the exact failure the whole mechanism exists to prevent.
# CI runs tests/test-*.sh and nothing else, so the real gate has to live here.
echo "8. this repository's own docs/_includes/terraform is in sync"
if OUT=$(bash "$SCRIPT" --root "$REPO_ROOT" --check 2>&1); then
  ok "${OUT}"
else
  bad "${OUT}"
  printf '         run: scripts/sync-terraform-includes.sh && git add docs/_includes\n'
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: terraform includes sync"
else
  echo "FAIL: terraform includes sync"
fi
exit "$FAIL"
