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
mkdir -p "$BIN" "$TF_DIR"
: >"$PLAN_FILE"

cat >"${BIN}/aws" <<'SH'
#!/usr/bin/env bash
printf '{"%s":"%s"}\n' 'Acc''ount' "${FAKE_AWS_ACCOUNT:-111122223333}"
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
  printf '{"provider_selections":{"registry.terraform.io/f5-sales-demo/xcsh":"7.4.1"}}\n'
  ;;
plan)
  : >"${chdir}/contract.tfplan"
  ;;
show)
  if [ "$chdir" = "$FAKE_TF_DIR" ]; then
    site_01_actions=${FAKE_SITE_01_ACTIONS:-${FAKE_SITE_ACTIONS:-'"create"'}}
    site_02_actions=${FAKE_SITE_02_ACTIONS:-${FAKE_SITE_ACTIONS:-'"create"'}}
    site_03_actions=${FAKE_SITE_03_ACTIONS:-${FAKE_SITE_ACTIONS:-'"create"'}}
    extra=${FAKE_EXTRA_CHANGE:-}
    if [ "${FAKE_TOKEN_ONLY:-false}" = true ]; then
      printf '{"resource_changes":[{"address":"xcsh_token.aws_01","type":"xcsh_token","name":"aws","change":{"actions":[%s],"after":{"site_name":"mcn-ce-ha-aws-ap-northeast-1-01"}}}%s]}\n' "$site_01_actions" "$extra"
    else
      printf '{"resource_changes":[{"address":"xcsh_securemesh_site_v2.aws_01","type":"xcsh_securemesh_site_v2","name":"aws","change":{"actions":[%s],"before":{"name":"mcn-ce-ha-aws-ap-northeast-1-01","namespace":"system"},"after":{"name":"mcn-ce-ha-aws-ap-northeast-1-01","namespace":"system"}}},{"address":"xcsh_securemesh_site_v2.aws_02","type":"xcsh_securemesh_site_v2","name":"aws","change":{"actions":[%s],"before":{"name":"mcn-ce-ha-aws-ap-northeast-1-02","namespace":"system"},"after":{"name":"mcn-ce-ha-aws-ap-northeast-1-02","namespace":"system"}}},{"address":"xcsh_securemesh_site_v2.aws_03","type":"xcsh_securemesh_site_v2","name":"aws","change":{"actions":[%s],"before":{"name":"mcn-ce-ha-aws-ap-northeast-1-03","namespace":"system"},"after":{"name":"mcn-ce-ha-aws-ap-northeast-1-03","namespace":"system"}}}%s]}\n' "$site_01_actions" "$site_02_actions" "$site_03_actions" "$extra"
    fi
  else
    capability=${FAKE_CAPABILITY_STATE:-available}
    printf '%s\n' "{\"planned_values\":{\"outputs\":{\"contract\":{\"value\":{\"contract_id\":\"f5xc-ce-automation/v3\",\"contract_version\":\"6.1.0\",\"api_release_tag\":\"v6.1.1\",\"api_release_commit\":\"2b27355ac9bf4683d3a321f7d6388676f756c2f5\",\"telemetry_schema_id\":\"f5xc-smsv2-aws-tgw-telemetry/v2\",\"capabilities\":{\"aws_ce_create\":\"${capability}\",\"runtime_status\":\"${capability}\",\"site_upgrade\":\"${capability}\",\"tgw_connect\":\"${capability}\"},\"f5xc_authorities\":[\"smsv2_configuration\",\"runtime_health\",\"bgp_peers\",\"bgp_routes\",\"simplified_routes\",\"site_upgrade_observation\"],\"aws_authorities\":[\"eni\",\"transit_gateway\",\"transit_gateway_connect\",\"gre_endpoints\",\"bgp_inside_cidrs\",\"autonomous_system_numbers\"]}}}}}"
  fi
  ;;
*) exit 2 ;;
esac
SH
chmod 755 "${BIN}/aws" "${BIN}/terraform"

export PATH="${BIN}:$PATH"
export FAKE_TF_DIR="$TF_DIR"
export AWS_REGION="ap-northeast-1"
export XCSH_API_URL="https://lab.console.ves.volterra.io"
export XCSH_API_TOKEN="test-token-must-not-leak"

common=(
  --terraform-dir "$TF_DIR"
  --plan-file "$PLAN_FILE"
  --expected-aws-account 111122223333
  --expected-aws-region ap-northeast-1
  --expected-xc-tenant lab
  --expected-site mcn-ce-ha-aws-ap-northeast-1-01
  --expected-site mcn-ce-ha-aws-ap-northeast-1-02
  --expected-site mcn-ce-ha-aws-ap-northeast-1-03
)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_sanitized() {
  local evidence=$1 output=$2
  [ "$(find "$evidence" -maxdepth 1 -type f -printf '%f\n')" = summary.json ] || fail "evidence contains unexpected files"
  [ "$(jq -r 'keys | sort | join(",")' "$evidence/summary.json")" = reason,status,timestamp ] || fail "summary has unexpected keys"
  if grep -R -E '111122223333|mcn-ce-ha-aws-ap-northeast-1|test-token-must-not-leak|lab\.console\.ves\.volterra\.io' "$evidence" "$output"; then
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

single_site=(
  --terraform-dir "$TF_DIR"
  --plan-file "$PLAN_FILE"
  --expected-aws-account 111122223333
  --expected-aws-region ap-northeast-1
  --expected-xc-tenant lab
  --expected-site mcn-ce-ha-aws-ap-northeast-1-01
)
evidence="${TMP_ROOT}/single-site"
mkdir "$evidence"
output="${TMP_ROOT}/single-site.out"
if ! FAKE_SITE_01_ACTIONS='"delete","create"' FAKE_SITE_02_ACTIONS='"no-op"' FAKE_SITE_03_ACTIONS='"no-op"' \
  "$SCRIPT" --evidence-dir "$evidence" "${single_site[@]}" >"$output" 2>&1; then
  cat "$output" >&2
  fail "one-site replacement must exclude unchanged peer sites"
fi
[ "$(jq -r .status "$evidence/summary.json")" = ready ] || fail "one-site replacement status not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - one-site replacement is accepted before the remaining sites"

evidence="${TMP_ROOT}/single-token"
mkdir "$evidence"
output="${TMP_ROOT}/single-token.out"
if ! FAKE_TOKEN_ONLY=true FAKE_SITE_01_ACTIONS='"create"' "$SCRIPT" --evidence-dir "$evidence" "${single_site[@]}" >"$output" 2>&1; then
  cat "$output" >&2
  fail "one-site JWT issuance must prove the site stage without forcing peer tokens"
fi
[ "$(jq -r .status "$evidence/summary.json")" = ready ] || fail "one-site JWT issuance status not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - site-scoped JWT issuance is accepted before the remaining sites"

evidence="${TMP_ROOT}/destroy"
mkdir "$evidence"
output="${TMP_ROOT}/destroy.out"
if ! FAKE_SITE_ACTIONS='"delete"' "$SCRIPT" --plan-mode destroy --evidence-dir "$evidence" "${common[@]}" >"$output" 2>&1; then
  cat "$output" >&2
  fail "AWS-only delete plan should pass destroy mode"
fi
[ "$(jq -r .status "$evidence/summary.json")" = ready ] || fail "destroy ready status not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - destroy mode accepts only the three expected site deletions"

evidence="${TMP_ROOT}/destroy-mixed"
mkdir "$evidence"
output="${TMP_ROOT}/destroy-mixed.out"
if FAKE_SITE_ACTIONS='"delete"' FAKE_EXTRA_CHANGE=',{"address":"aws_instance.unexpected","type":"aws_instance","name":"unexpected","change":{"actions":["create"],"after":{}}}' \
  "$SCRIPT" --plan-mode destroy --evidence-dir "$evidence" "${common[@]}" >"$output" 2>&1; then
  fail "destroy mode must reject non-delete actions"
fi
[ "$(jq -r .reason "$evidence/summary.json")" = destroy_plan_contains_non_delete_actions ] || fail "mixed destroy blocker not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - destroy mode rejects non-delete actions"

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

evidence="${TMP_ROOT}/azure-change"
mkdir "$evidence"
output="${TMP_ROOT}/azure-change.out"
if FAKE_EXTRA_CHANGE=',{"address":"azurerm_virtual_network.hub","type":"azurerm_virtual_network","name":"hub","change":{"actions":["update"],"after":{}}}' \
  "$SCRIPT" --evidence-dir "$evidence" "${common[@]}" >"$output" 2>&1; then
  fail "any Azure action must block"
fi
[ "$(jq -r .reason "$evidence/summary.json")" = azure_changes_present ] || fail "Azure-change blocker not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - an Azure change is rejected without Azure CLI access"

evidence="${TMP_ROOT}/outside-allowlist"
mkdir "$evidence"
output="${TMP_ROOT}/outside-allowlist.out"
if FAKE_EXTRA_CHANGE=',{"address":"random_id.unrelated","type":"random_id","name":"unrelated","change":{"actions":["create"],"after":{}}}' \
  "$SCRIPT" --evidence-dir "$evidence" "${common[@]}" >"$output" 2>&1; then
  fail "a change outside the AWS/XC-AWS allowlist must block"
fi
[ "$(jq -r .reason "$evidence/summary.json")" = plan_resource_outside_aws_allowlist ] || fail "allowlist blocker not recorded"
assert_sanitized "$evidence" "$output"
echo "ok - changes outside the AWS/XC-AWS allowlist fail closed"

mkdir "$INSIDE_EVIDENCE"
if "$SCRIPT" --evidence-dir "$INSIDE_EVIDENCE" "${common[@]}" >/dev/null 2>&1; then
  fail "repository-local evidence directory must be rejected"
fi
echo "ok - repository-local evidence is rejected"

echo "PASS: AWS SMSv2 UAT preflight shell tests"
