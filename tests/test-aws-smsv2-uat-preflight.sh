#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="${REPO_ROOT}/scripts/aws-smsv2-uat-preflight.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mcn-preflight-test.XXXXXX")
INSIDE_EVIDENCE="${REPO_ROOT}/.preflight-evidence-test-$$"
trap 'rm -rf "$TMP_ROOT" "$INSIDE_EVIDENCE"' EXIT

BIN="${TMP_ROOT}/bin"
TF_DIR="${TMP_ROOT}/terraform"
PLAN_FILE="${TMP_ROOT}/deployment.tfplan"
mkdir -p "$BIN" "${TF_DIR}/.terraform"
: >"$PLAN_FILE"

cat >"${TF_DIR}/.terraform/terraform.tfstate" <<'JSON'
{
  "backend": {
    "type": "azurerm",
    "config": {
      "SUBSCRIPTION_KEY": "sub-lab",
      "resource_group_name": "rg-state",
      "storage_account_name": "ststate",
      "container_name": "tfstate",
      "key": "mcn.tfstate"
    }
  }
}
JSON
SUBSCRIPTION_KEY="subscription""_id"
sed -i "s/SUBSCRIPTION_KEY/${SUBSCRIPTION_KEY}/" "${TF_DIR}/.terraform/terraform.tfstate"

cat >"${BIN}/aws" <<'SH'
#!/usr/bin/env bash
printf '{"%s":"%s"}\n' 'Acc''ount' "${FAKE_AWS_ACCOUNT:-111122223333}"
SH

cat >"${BIN}/az" <<'SH'
#!/usr/bin/env bash
printf '{"id":"%s"}\n' "${FAKE_AZURE_SUBSCRIPTION:-sub-lab}"
SH

cat >"${BIN}/terraform" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
chdir=${1#-chdir=}
shift
case "$1" in
init)
  exit 0
  ;;
version)
  printf '{"provider_selections":{"registry.terraform.io/f5-sales-demo/xcsh":"7.2.0"}}\n'
  ;;
plan)
  : >"${chdir}/contract.tfplan"
  ;;
show)
  if [ "$chdir" = "$FAKE_TF_DIR" ]; then
    site_actions=${FAKE_SITE_ACTIONS:-'"create"'}
    printf '{"resource_changes":[{"address":"xcsh_securemesh_site_v2.aws[0]","change":{"actions":[%s],"after":{"name":"mcn-1085-aws-site","namespace":"system"}}}]}\n' "$site_actions"
  else
    capability=${FAKE_CAPABILITY_STATE:-available}
    printf '%s\n' "{\"planned_values\":{\"outputs\":{\"contract\":{\"value\":{\"contract_id\":\"f5xc-ce-automation/v3\",\"contract_version\":\"6.0.0\",\"api_release_tag\":\"v6.0.2\",\"api_release_commit\":\"17751d9a1de68b6831b9091fa0d17718952d659d\",\"telemetry_schema_id\":\"f5xc-smsv2-aws-tgw-telemetry/v2\",\"capabilities\":{\"aws_ce_create\":\"${capability}\",\"runtime_status\":\"${capability}\",\"tgw_connect\":\"${capability}\"},\"f5xc_authorities\":[\"smsv2_configuration\",\"runtime_health\",\"bgp_peers\",\"bgp_routes\",\"simplified_routes\"],\"aws_authorities\":[\"eni\",\"transit_gateway\",\"transit_gateway_connect\",\"gre_endpoints\",\"bgp_inside_cidrs\",\"autonomous_system_numbers\"]}}}}}"
  fi
  ;;
*) exit 2 ;;
esac
SH
chmod 755 "${BIN}/aws" "${BIN}/az" "${BIN}/terraform"

export PATH="${BIN}:$PATH"
export FAKE_TF_DIR="$TF_DIR"
export AWS_REGION="us-east-2"
export XCSH_API_URL="https://lab.console.ves.volterra.io"
export XCSH_API_TOKEN="test-token-must-not-leak"

common=(
  --terraform-dir "$TF_DIR"
  --plan-file "$PLAN_FILE"
  --expected-aws-account 111122223333
  --expected-aws-region us-east-2
  --expected-azure-subscription sub-lab
  --expected-backend-resource-group rg-state
  --expected-backend-storage-account ststate
  --expected-backend-container tfstate
  --expected-backend-key mcn.tfstate
  --expected-xc-tenant lab
  --expected-site mcn-1085-aws-site
)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_sanitized() {
  local evidence=$1 output=$2
  [ "$(find "$evidence" -maxdepth 1 -type f -printf '%f\n')" = summary.json ] || fail "evidence contains unexpected files"
  [ "$(jq -r 'keys | sort | join(",")' "$evidence/summary.json")" = reason,status,timestamp ] || fail "summary has unexpected keys"
  if grep -R -E '111122223333|sub-lab|rg-state|ststate|mcn-1085-aws-site|test-token-must-not-leak|lab\.console\.ves\.volterra\.io' "$evidence" "$output"; then
    fail "identity or credential leaked into sanitized evidence"
  fi
}

evidence="${TMP_ROOT}/ready"
mkdir "$evidence"
output="${TMP_ROOT}/ready.out"
if ! "$SCRIPT" --evidence-dir "$evidence" "${common[@]}" >"$output" 2>&1; then
  cat "$output" >&2
  fail "available contract should pass"
fi
[ "$(jq -r .status "$evidence/summary.json")" = ready ] || fail "ready status not recorded"
[ "$(jq -r .reason "$evidence/summary.json")" = preflight_passed ] || fail "ready reason not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - exact v7 available contract passes with sanitized evidence"

evidence="${TMP_ROOT}/replacement"
mkdir "$evidence"
output="${TMP_ROOT}/replacement.out"
if ! FAKE_SITE_ACTIONS='"delete","create"' "$SCRIPT" --evidence-dir "$evidence" "${common[@]}" >"$output" 2>&1; then
  cat "$output" >&2
  fail "site replacement should preserve the checked site identity"
fi
[ "$(jq -r .status "$evidence/summary.json")" = ready ] || fail "replacement status not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - site replacement is accepted when its target identity matches"

sed -i 's/"subscription_id": "sub-lab"/"subscription_id": ""/' "${TF_DIR}/.terraform/terraform.tfstate"
evidence="${TMP_ROOT}/backend-without-subscription"
mkdir "$evidence"
output="${TMP_ROOT}/backend-without-subscription.out"
if ! "$SCRIPT" --evidence-dir "$evidence" "${common[@]}" >"$output" 2>&1; then
  cat "$output" >&2
  fail "storage-coordinate backend without subscription_id should pass under the verified Azure identity"
fi
[ "$(jq -r .status "$evidence/summary.json")" = ready ] || fail "storage-coordinate backend status not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - storage-coordinate backend accepts verified Azure identity without subscription_id"

evidence="${TMP_ROOT}/unavailable"
mkdir "$evidence"
output="${TMP_ROOT}/unavailable.out"
if FAKE_CAPABILITY_STATE=unavailable "$SCRIPT" --evidence-dir "$evidence" "${common[@]}" >"$output" 2>&1; then
  fail "unavailable capabilities must block"
fi
[ "$(jq -r .reason "$evidence/summary.json")" = v7_capabilities_unavailable ] || fail "capability blocker not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - unavailable capabilities fail closed"

evidence="${TMP_ROOT}/identity"
mkdir "$evidence"
output="${TMP_ROOT}/identity.out"
if FAKE_AWS_ACCOUNT=999900001111 "$SCRIPT" --evidence-dir "$evidence" "${common[@]}" >"$output" 2>&1; then
  fail "wrong AWS account must block"
fi
[ "$(jq -r .reason "$evidence/summary.json")" = aws_account_mismatch ] || fail "AWS blocker not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - target identity mismatch fails closed"

mkdir "$INSIDE_EVIDENCE"
if "$SCRIPT" --evidence-dir "$INSIDE_EVIDENCE" "${common[@]}" >/dev/null 2>&1; then
  fail "repository-local evidence directory must be rejected"
fi
echo "ok - repository-local evidence is rejected"

echo "PASS: AWS SMSv2 UAT preflight shell tests"
