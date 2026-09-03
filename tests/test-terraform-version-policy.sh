#!/usr/bin/env bash
# Regression guard for the released SMSv2 clean-break provider boundary.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKFLOW="${REPO_ROOT}/.github/workflows/terraform.yml"
EXAMPLE="${REPO_ROOT}/terraform/terraform.tfvars.example"
FAIL=0

ok() { printf '  ok   — %s\n' "$1"; }
bad() {
  printf '  FAIL — %s\n' "$1"
  FAIL=1
}

echo "1. Terraform CLI remains unpinned"
if [ -e "${REPO_ROOT}/terraform/.terraform-version" ]; then
  bad "terraform/.terraform-version pins the Terraform CLI"
else
  ok "no local Terraform CLI pin"
fi
if grep -Eq '^[[:space:]]*terraform_version:' "$WORKFLOW"; then
  bad "Terraform workflow supplies a pinned Terraform CLI"
else
  ok "setup-terraform uses its latest-version default"
fi

echo "2. every xcsh consumer pins exactly v7.0.0"
for relative in terraform/versions.tf terraform/modules/xc-site/versions.tf coverage/smsv2/versions.tf; do
  file="${REPO_ROOT}/${relative}"
  block=$(sed -n '/^[[:space:]]*xcsh = {/,/^[[:space:]]*}/p' "$file")
  if printf '%s\n' "$block" | grep -Eq 'version[[:space:]]*=[[:space:]]*"= 7\.0\.0"'; then
    ok "${relative} pins = 7.0.0"
  else
    bad "${relative} does not pin exactly = 7.0.0"
  fi
  count=$(printf '%s\n' "$block" | grep -Ec '^[[:space:]]*version[[:space:]]*=' || true)
  [ "$count" -eq 1 ] || bad "${relative} has ${count} xcsh version constraints"
done

for relative in .github/workflows/terraform.yml prompt.txt docs/en/demo/deploy.mdx \
  docs/en/demo/prompt.mdx docs/en/demo/spec.mdx docs/en/demo/terraform.mdx \
  tests/test-verify-deployment.sh; do
  if grep -Fq '7.0.0' "${REPO_ROOT}/${relative}"; then
    ok "${relative} references v7.0.0"
  else
    bad "${relative} is missing the v7.0.0 reference"
  fi
done
legacy_version='6''.''1''.''2'
if grep -R -n -F --exclude-dir=.terraform "$legacy_version" \
  "${REPO_ROOT}/terraform" "${REPO_ROOT}/coverage/smsv2" \
  "${REPO_ROOT}/.github/workflows/terraform.yml" "${REPO_ROOT}/prompt.txt" \
  "${REPO_ROOT}/docs/en"; then
  bad "a legacy provider consumer or English reference remains"
else
  ok "no legacy provider consumer or English reference remains"
fi

source_count=$(grep -R -lF 'source  = "f5-sales-demo/xcsh"' \
  "${REPO_ROOT}/terraform" "${REPO_ROOT}/coverage/smsv2" --include='*.tf' | wc -l)
if [ "$source_count" -eq 3 ]; then
  ok "the three known xcsh consumers are the complete provider surface"
else
  bad "expected exactly three xcsh provider declarations, found ${source_count}"
fi

echo "3. the v7 clean break has no legacy observation-freshness inputs"
if grep -R -n -E 'aws_bgp_max_observation_age_seconds|max_observation_age_seconds|observed_at' \
  "${REPO_ROOT}/terraform" --include='*.tf' --include='*.tftest.hcl'; then
  bad "legacy observation freshness fields remain in Terraform"
else
  ok "Terraform uses deadline/poll controls and state_changed_at only"
fi

echo "4. provider resolution is clean and reproducible"
if git -C "$REPO_ROOT" ls-files --error-unmatch terraform/.terraform.lock.hcl >/dev/null 2>&1; then
  bad "terraform lockfile is committed"
else
  ok "Terraform lockfile remains uncommitted"
fi
if grep -Eq '^\.terraform\.lock\.hcl([[:space:]]|$)' "${REPO_ROOT}/.gitignore"; then
  ok "local lockfile remains ignored"
else
  bad "local lockfile is not ignored"
fi

echo "5. the fresh-clone example keeps environment values external"
for assignment in 'ce_os_version = ""' 'ce_sw_version = ""' 'lb_domain = "mcn-ce-ha.example.com"' 'subscription_id = "<AZURE_SUBSCRIPTION_ID>"' 'xc_app_namespace = "demo-app"'; do
  if grep -Fqx "$assignment" "$EXAMPLE"; then
    ok "example contains ${assignment}"
  else
    bad "example is missing ${assignment}"
  fi
done
if grep -Fq 'f5-sales-demo.' "$EXAMPLE"; then
  bad "example publishes a deployment-specific domain"
else
  ok "example contains no deployment-specific domain"
fi

echo "6. policy-test edits trigger Terraform CI"
trigger_count=$(grep -cF "'tests/test-terraform-version-policy.sh'" "$WORKFLOW" || true)
if [ "$trigger_count" -eq 2 ]; then
  ok "pull_request and push watch the policy test"
else
  bad "expected two workflow path filters, found ${trigger_count}"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: Terraform version policy"
else
  echo "FAIL: Terraform version policy"
fi
exit "$FAIL"
