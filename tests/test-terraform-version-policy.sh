#!/usr/bin/env bash
# Regression guard for MCN's deliberate "latest, unpinned" Terraform policy.
# Compatibility floors remain where the configuration requires them, but local
# and CI initialization must resolve the newest compatible Terraform/provider.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKFLOW="${REPO_ROOT}/.github/workflows/terraform.yml"
VERSIONS="${REPO_ROOT}/terraform/versions.tf"
EXAMPLE="${REPO_ROOT}/terraform/terraform.tfvars.example"

FAIL=0

ok() { printf '  ok   — %s\n' "$1"; }
bad() {
  printf '  FAIL — %s\n' "$1"
  FAIL=1
}

echo "1. Terraform tooling resolves latest"
if [ -e "${REPO_ROOT}/terraform/.terraform-version" ]; then
  bad "terraform/.terraform-version pins the Terraform CLI"
else
  ok "no local Terraform CLI pin"
fi

if grep -Eq '^[[:space:]]*terraform_version:' "$WORKFLOW"; then
  bad "Terraform workflow supplies a pinned terraform_version"
else
  ok "setup-terraform uses its latest-version default"
fi

echo "2. xcsh retains only its required compatibility floor"
XCSH_BLOCK=$(sed -n '/^[[:space:]]*xcsh = {/,/^[[:space:]]*}/p' "$VERSIONS")
if printf '%s\n' "$XCSH_BLOCK" | grep -Eq 'version[[:space:]]*=[[:space:]]*">= 3\.81\.1"'; then
  ok "xcsh has the required open minimum"
else
  bad "xcsh constraint is not the required open minimum >= 3.81.1"
fi

if printf '%s\n' "$XCSH_BLOCK" | grep -Eq 'version[[:space:]]*=.*(~>|<|,)'; then
  bad "xcsh constraint contains an upper bound or pessimistic pin"
else
  ok "xcsh has no upper bound"
fi

echo "3. provider resolution is intentionally unpinned"
if git -C "$REPO_ROOT" ls-files --error-unmatch terraform/.terraform.lock.hcl >/dev/null 2>&1; then
  bad "terraform/.terraform.lock.hcl is committed"
else
  ok "Terraform lockfile is not committed"
fi

if grep -Eq '^\.terraform\.lock\.hcl([[:space:]]|$)' "${REPO_ROOT}/.gitignore"; then
  ok "local lockfile remains ignored"
else
  bad "local lockfile is not ignored"
fi

echo "4. the fresh-clone example pins the measured CE fallback"
for assignment in \
  'ce_os_version = "9.2024.6"' \
  'ce_sw_version = "crt-20250613-3382"' \
  'lb_domain = "mcn-ce-ha.example.com"' \
  'subscription_id = "<AZURE_SUBSCRIPTION_ID>"' \
  'xc_app_namespace = "demo-app"'; do
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

echo "5. policy-test edits trigger Terraform CI"
trigger_count=$(grep -cF "'tests/test-terraform-version-policy.sh'" "$WORKFLOW" || true)
if [ "$trigger_count" -eq 2 ]; then
  ok "pull_request and push both watch the policy test"
else
  bad "expected two workflow path filters for the policy test, found ${trigger_count}"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: Terraform version policy"
else
  echo "FAIL: Terraform version policy"
fi
exit "$FAIL"
