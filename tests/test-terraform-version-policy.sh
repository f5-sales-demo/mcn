#!/usr/bin/env bash
# Regression guard for the unreleased SMSv2 clean-break provider boundary.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKFLOW="${REPO_ROOT}/.github/workflows/terraform.yml"
EXAMPLE="${REPO_ROOT}/terraform/terraform.tfvars.example"
FAIL=0

ok() { printf '  ok   — %s\n' "$1"; }
bad() { printf '  FAIL — %s\n' "$1"; FAIL=1; }

echo "1. Terraform CLI remains unpinned"
if [ -e "${REPO_ROOT}/terraform/.terraform-version" ]; then bad "terraform/.terraform-version pins the Terraform CLI"; else ok "no local Terraform CLI pin"; fi
if grep -Eq '^[[:space:]]*terraform_version:' "$WORKFLOW"; then bad "Terraform workflow supplies a pinned Terraform CLI"; else ok "setup-terraform uses its latest-version default"; fi

echo "2. every xcsh consumer pins exactly v6.0.0"
for relative in terraform/versions.tf terraform/modules/xc-site/versions.tf coverage/smsv2/versions.tf; do
  file="${REPO_ROOT}/${relative}"
  block=$(sed -n '/^[[:space:]]*xcsh = {/,/^[[:space:]]*}/p' "$file")
  if printf '%s\n' "$block" | grep -Eq 'version[[:space:]]*=[[:space:]]*"= 6\.0\.0"'; then
    ok "${relative} pins = 6.0.0"
  else
    bad "${relative} does not pin exactly = 6.0.0"
  fi
  count=$(printf '%s\n' "$block" | grep -Ec '^[[:space:]]*version[[:space:]]*=' || true)
  [ "$count" -eq 1 ] || bad "${relative} has ${count} xcsh version constraints"
done

source_count=$(grep -R -lF 'source  = "f5-sales-demo/xcsh"' \
  "${REPO_ROOT}/terraform" "${REPO_ROOT}/coverage/smsv2" --include='*.tf' | wc -l)
if [ "$source_count" -eq 3 ]; then
  ok "the three known xcsh consumers are the complete provider surface"
else
  bad "expected exactly three xcsh provider declarations, found ${source_count}"
fi

echo "3. provider resolution is clean and reproducible"
if git -C "$REPO_ROOT" ls-files --error-unmatch terraform/.terraform.lock.hcl >/dev/null 2>&1; then bad "terraform lockfile is committed"; else ok "Terraform lockfile remains uncommitted"; fi
if grep -Eq '^\.terraform\.lock\.hcl([[:space:]]|$)' "${REPO_ROOT}/.gitignore"; then ok "local lockfile remains ignored"; else bad "local lockfile is not ignored"; fi

echo "4. the fresh-clone example keeps environment values external"
for assignment in 'ce_os_version = ""' 'ce_sw_version = ""' 'lb_domain = "mcn-ce-ha.example.com"' 'subscription_id = "<AZURE_SUBSCRIPTION_ID>"' 'xc_app_namespace = "demo-app"'; do
  grep -Fqx "$assignment" "$EXAMPLE" && ok "example contains ${assignment}" || bad "example is missing ${assignment}"
done
if grep -Fq 'f5-sales-demo.' "$EXAMPLE"; then bad "example publishes a deployment-specific domain"; else ok "example contains no deployment-specific domain"; fi

echo "5. policy-test edits trigger Terraform CI"
trigger_count=$(grep -cF "'tests/test-terraform-version-policy.sh'" "$WORKFLOW" || true)
[ "$trigger_count" -eq 2 ] && ok "pull_request and push watch the policy test" || bad "expected two workflow path filters, found ${trigger_count}"

[ "$FAIL" -eq 0 ] && echo "PASS: Terraform version policy" || echo "FAIL: Terraform version policy"
exit "$FAIL"
