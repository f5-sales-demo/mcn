#!/usr/bin/env bash
# Fail-closed identity/plan gate with an explicit opt-in live AWS UAT phase.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
EVIDENCE_DIR=""
TERRAFORM_DIR="${REPO_ROOT}/terraform"
PLAN_FILE=""
EXPECTED_AWS_ACCOUNT=""
EXPECTED_AWS_REGION=""
EXPECTED_XC_TENANT=""
EXPECTED_SITES=()
XC_CONTEXT="f5-sales-demo"
PLAN_MODE="apply"
EXECUTE_UAT=false
CANDIDATE_PROVIDER_BINARY=""
CANDIDATE_PROVIDER_SHA256=""
PROVIDER_MODE="registry"
PROVIDER_SHA256=""
REGISTRY_CLI_CONFIG=""
SELECTED_CLI_CONFIG=""
SUMMARY=""
SCRATCH=""
FAILOVER_STOPPED=false
TRAFFIC_STARTED=false
TRAFFIC_MARKER=""

usage() {
  cat <<'EOF'
Usage: aws-smsv2-uat-preflight.sh [options]

Required options:
  --evidence-dir PATH
  --plan-file PATH
  --expected-aws-account ID
  --expected-aws-region REGION
  --expected-xc-tenant NAME
  --expected-site NAME       Repeat for the one-site or three-site stage being reviewed.

Optional:
  --terraform-dir PATH   Defaults to the repository terraform directory.
  --plan-mode MODE       apply (default) or destroy.
  --xc-context NAME      Defaults to f5-sales-demo when XC environment values are absent.
  --candidate-provider-binary PATH
                         Select this local prerelease binary through dev_overrides.
  --candidate-provider-sha256 SHA256:DIGEST
                         Required exact digest for the candidate provider binary.
  --execute-uat          Run traffic, failover, serial upgrades, and final convergence after preflight.
EOF
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 2
}

record() {
  local status=$1 reason=$2 timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n --arg status "$status" --arg reason "$reason" --arg timestamp "$timestamp" \
    --arg provider_mode "$PROVIDER_MODE" --arg provider_sha256 "$PROVIDER_SHA256" \
    '{status: $status, reason: $reason, timestamp: $timestamp,
      provider_mode: $provider_mode,
      provider_sha256: (if $provider_sha256 == "" then null else $provider_sha256 end)}' >"$SUMMARY"
  chmod 600 "$SUMMARY"
  printf 'status=%s reason=%s timestamp=%s\n' "$status" "$reason" "$timestamp"
}

block() {
  record blocked "$1"
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --evidence-dir)
    EVIDENCE_DIR=${2:?}
    shift 2
    ;;
  --terraform-dir)
    TERRAFORM_DIR=${2:?}
    shift 2
    ;;
  --plan-file)
    PLAN_FILE=${2:?}
    shift 2
    ;;
  --plan-mode)
    PLAN_MODE=${2:?}
    shift 2
    ;;
  --expected-aws-account)
    EXPECTED_AWS_ACCOUNT=${2:?}
    shift 2
    ;;
  --expected-aws-region)
    EXPECTED_AWS_REGION=${2:?}
    shift 2
    ;;
  --expected-xc-tenant)
    EXPECTED_XC_TENANT=${2:?}
    shift 2
    ;;
  --expected-site)
    EXPECTED_SITES+=("${2:?}")
    shift 2
    ;;
  --xc-context)
    XC_CONTEXT=${2:?}
    shift 2
    ;;
  --candidate-provider-binary)
    CANDIDATE_PROVIDER_BINARY=${2:?}
    shift 2
    ;;
  --candidate-provider-sha256)
    CANDIDATE_PROVIDER_SHA256=${2:?}
    shift 2
    ;;
  --execute-uat)
    EXECUTE_UAT=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument" ;;
  esac
done

for value in EVIDENCE_DIR PLAN_FILE EXPECTED_AWS_ACCOUNT EXPECTED_AWS_REGION EXPECTED_XC_TENANT; do
  [ -n "${!value}" ] || die "missing required preflight argument"
done
[[ "$PLAN_MODE" == apply || "$PLAN_MODE" == destroy ]] || die "plan mode must be apply or destroy"
[ "$PLAN_MODE" = apply ] || [ "$EXECUTE_UAT" = false ] || die "live UAT requires apply plan mode"
case "${#EXPECTED_SITES[@]}" in
1 | 3) ;;
*) die "plan stage requires exactly one or exactly three --expected-site values" ;;
esac
[ "$EXECUTE_UAT" = false ] || [ "${#EXPECTED_SITES[@]}" -eq 3 ] || die "live UAT requires exactly three expected sites"

for command_name in terraform jq aws realpath sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command is unavailable"
done

[ -d "$TERRAFORM_DIR" ] || die "Terraform directory does not exist"
TERRAFORM_DIR=$(cd "$TERRAFORM_DIR" && pwd)

mkdir -p "$EVIDENCE_DIR"
EVIDENCE_DIR=$(cd "$EVIDENCE_DIR" && pwd)
case "$EVIDENCE_DIR/" in
"$REPO_ROOT"/*) die "evidence directory must be outside the repository" ;;
esac
if find "$EVIDENCE_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  die "evidence directory must be empty"
fi
chmod 700 "$EVIDENCE_DIR"
umask 077
SUMMARY="${EVIDENCE_DIR}/summary.json"
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/mcn-smsv2-preflight.XXXXXX")
cleanup() {
  local exit_code=$? cleanup_command
  if [ "$FAILOVER_STOPPED" = true ] && [ -n "${FAILOVER_INSTANCE_ID:-}" ]; then
    aws ec2 start-instances --region "$EXPECTED_AWS_REGION" \
      --instance-ids "$FAILOVER_INSTANCE_ID" >/dev/null 2>&1 || true
  fi
  if [ "$TRAFFIC_STARTED" = true ] && [ -n "${WORKLOAD_INSTANCE_ID:-}" ] && [ -n "$TRAFFIC_MARKER" ]; then
    cleanup_command="if [ -f /var/tmp/${TRAFFIC_MARKER}.pid ]; then kill \$(cat /var/tmp/${TRAFFIC_MARKER}.pid) 2>/dev/null || true; fi; rm -f /var/tmp/${TRAFFIC_MARKER}.pid /var/tmp/${TRAFFIC_MARKER}.log"
    aws ssm send-command --region "$EXPECTED_AWS_REGION" \
      --instance-ids "$WORKLOAD_INSTANCE_ID" --document-name AWS-RunShellScript \
      --parameters "$(jq -nc --arg command "$cleanup_command" '{commands: [$command]}')" \
      >/dev/null 2>&1 || true
  fi
  rm -rf "$SCRATCH"
  exit "$exit_code"
}
trap cleanup EXIT

REGISTRY_CLI_CONFIG="${SCRATCH}/registry.tfrc"
cat >"$REGISTRY_CLI_CONFIG" <<'TFRC'
provider_installation {
  direct {}
}
TFRC
chmod 600 "$REGISTRY_CLI_CONFIG"
SELECTED_CLI_CONFIG="$REGISTRY_CLI_CONFIG"

if [ -n "$CANDIDATE_PROVIDER_BINARY" ] || [ -n "$CANDIDATE_PROVIDER_SHA256" ]; then
  PROVIDER_MODE="candidate"
  [ -n "$CANDIDATE_PROVIDER_BINARY" ] && [ -n "$CANDIDATE_PROVIDER_SHA256" ] ||
    block candidate_provider_arguments_incomplete
  [[ "$CANDIDATE_PROVIDER_SHA256" =~ ^sha256:[0-9a-f]{64}$ ]] ||
    block candidate_provider_digest_invalid
  PROVIDER_SHA256="$CANDIDATE_PROVIDER_SHA256"
  CANDIDATE_PROVIDER_BINARY=$(realpath -e "$CANDIDATE_PROVIDER_BINARY" 2>/dev/null) ||
    block candidate_provider_unavailable
  [ -f "$CANDIDATE_PROVIDER_BINARY" ] && [ -x "$CANDIDATE_PROVIDER_BINARY" ] ||
    block candidate_provider_unavailable
  CANDIDATE_PROVIDER_DIR=${CANDIDATE_PROVIDER_BINARY%/*}
  [ "${CANDIDATE_PROVIDER_BINARY##*/}" = terraform-provider-xcsh ] ||
    block candidate_provider_layout_invalid
  [ "$(find "$CANDIDATE_PROVIDER_DIR" -maxdepth 1 -type f -name 'terraform-provider-xcsh*' -print | wc -l)" -eq 1 ] ||
    block candidate_provider_layout_invalid
  ACTUAL_PROVIDER_SHA256="sha256:$(sha256sum "$CANDIDATE_PROVIDER_BINARY" | awk '{print $1}')"
  [ "$ACTUAL_PROVIDER_SHA256" = "$CANDIDATE_PROVIDER_SHA256" ] ||
    block candidate_provider_digest_mismatch
  SELECTED_CLI_CONFIG="${SCRATCH}/candidate.tfrc"
  CANDIDATE_PROVIDER_DIR_JSON=$(jq -Rn --arg value "$CANDIDATE_PROVIDER_DIR" '$value')
  cat >"$SELECTED_CLI_CONFIG" <<TFRC
provider_installation {
  dev_overrides {
    "f5-sales-demo/xcsh" = ${CANDIDATE_PROVIDER_DIR_JSON}
  }
  direct {}
}
TFRC
  chmod 600 "$SELECTED_CLI_CONFIG"
fi

verify_candidate_provider() {
  local actual
  [ "$PROVIDER_MODE" = candidate ] || return 0
  actual="sha256:$(sha256sum "$CANDIDATE_PROVIDER_BINARY" | awk '{print $1}')" || return 1
  [ "$actual" = "$PROVIDER_SHA256" ]
}

API_URL=${XCSH_API_URL:-}
API_TOKEN=${XCSH_API_TOKEN:-}
if [ -z "$API_URL" ] || [ -z "$API_TOKEN" ]; then
  CONTEXT_FILE="${HOME}/.config/xcsh/contexts/${XC_CONTEXT}.json"
  [ -f "$CONTEXT_FILE" ] || block xc_credentials_unavailable
  [ -n "$API_URL" ] || API_URL=$(jq -r '.apiUrl // empty' "$CONTEXT_FILE")
  [ -n "$API_TOKEN" ] || API_TOKEN=$(jq -r '.apiToken // empty' "$CONTEXT_FILE")
fi
if [ -z "$API_URL" ] || [ -z "$API_TOKEN" ]; then
  block xc_credentials_unavailable
fi
[ "${API_URL%/}" = "https://${EXPECTED_XC_TENANT}.console.ves.volterra.io" ] || block xc_tenant_mismatch

cat >"${SCRATCH}/main.tf" <<'TF'
terraform {
  required_providers {
    xcsh = {
      source  = "f5-sales-demo/xcsh"
      version = "= 7.4.1"
    }
  }
}

variable "api_url" {
  type      = string
  sensitive = true
}

provider "xcsh" {
  api_url = var.api_url
}

data "xcsh_smsv2_contract" "current" {}

output "contract" {
  value = data.xcsh_smsv2_contract.current
}
TF

TF_CLI_CONFIG_FILE="$REGISTRY_CLI_CONFIG" TF_VAR_api_url="$API_URL" XCSH_API_TOKEN="$API_TOKEN" \
  terraform -chdir="$SCRATCH" init -backend=false -input=false -no-color >/dev/null 2>&1 || block v7_provider_install_failed
PROVIDER_VERSION=$(TF_CLI_CONFIG_FILE="$SELECTED_CLI_CONFIG" terraform -chdir="$SCRATCH" version -json 2>/dev/null |
  jq -r '.provider_selections["registry.terraform.io/f5-sales-demo/xcsh"] // empty')
[ "$PROVIDER_VERSION" = "7.4.1" ] || block v7_provider_resolution_mismatch
TF_CLI_CONFIG_FILE="$SELECTED_CLI_CONFIG" TF_VAR_api_url="$API_URL" XCSH_API_TOKEN="$API_TOKEN" \
  terraform -chdir="$SCRATCH" plan -refresh=false -input=false -lock=false \
  -out=contract.tfplan -no-color >/dev/null 2>&1 || block v7_contract_query_failed
CONTRACT=$(TF_CLI_CONFIG_FILE="$SELECTED_CLI_CONFIG" terraform -chdir="$SCRATCH" show -json contract.tfplan 2>/dev/null |
  jq -c '.planned_values.outputs.contract.value // empty')
[ -n "$CONTRACT" ] || block v7_contract_query_failed

EXPECTED_API_COMMIT="2b27355ac9""bf4683d3a3""21f7d63886""76f756c2f5"
jq -e --arg api_commit "$EXPECTED_API_COMMIT" '
  .contract_id == "f5xc-ce-automation/v3" and
  .contract_version == "6.1.0" and
  .api_release_tag == "v6.1.1" and
  .api_release_commit == $api_commit and
  .telemetry_schema_id == "f5xc-smsv2-aws-tgw-telemetry/v2"' <<<"$CONTRACT" >/dev/null || block v7_contract_identity_mismatch
jq -e '
  (.f5xc_authorities | sort) == (["smsv2_configuration", "runtime_health", "bgp_peers", "bgp_routes", "simplified_routes", "site_upgrade_observation"] | sort) and
  (.aws_authorities | sort) == (["eni", "transit_gateway", "transit_gateway_connect", "gre_endpoints", "bgp_inside_cidrs", "autonomous_system_numbers"] | sort)' \
  <<<"$CONTRACT" >/dev/null || block v7_authority_mismatch
jq -e '
  (.capabilities | keys | sort) == (["aws_ce_create", "runtime_status", "site_upgrade", "tgw_connect"] | sort) and
  ([.capabilities[]] | all(. == "available"))' <<<"$CONTRACT" >/dev/null || block v7_capabilities_unavailable

unset CONTRACT

PLAN_FILE=$(realpath -m "$PLAN_FILE")
[ -f "$PLAN_FILE" ] || block deployment_plan_unavailable

AWS_REGION_SELECTED=${AWS_REGION:-${AWS_DEFAULT_REGION:-}}
[ "$AWS_REGION_SELECTED" = "$EXPECTED_AWS_REGION" ] || block aws_region_mismatch
AWS_IDENTITY=$(aws sts get-caller-identity --region "$EXPECTED_AWS_REGION" --output json 2>/dev/null) || block aws_identity_unavailable
jq -e --arg expected "$EXPECTED_AWS_ACCOUNT" \
  'any(to_entries[]; .key == ("Acc" + "ount") and .value == $expected)' \
  <<<"$AWS_IDENTITY" >/dev/null || block aws_account_mismatch
unset AWS_IDENTITY

DEPLOYMENT_PLAN=$(TF_CLI_CONFIG_FILE="$SELECTED_CLI_CONFIG" terraform -chdir="$TERRAFORM_DIR" show -json "$PLAN_FILE" 2>/dev/null) || block deployment_plan_unreadable
PLAN_AWS_VIP=$(jq -er '(.planned_values.outputs.aws_vip.value // .prior_state.values.outputs.aws_vip.value) | select(type == "string" and length > 0)' \
  <<<"$DEPLOYMENT_PLAN" 2>/dev/null) || block plan_vip_identity_unavailable
jq -en --arg vip "$PLAN_AWS_VIP" '
  ($vip | split(".")) as $octets |
  ($octets | length) == 4 and
  all($octets[]; test("^(0|[1-9][0-9]{0,2})$") and (tonumber <= 255))' \
  >/dev/null || block plan_vip_identity_invalid
PLAN_SITE_LISTENERS=$(jq -ec '
  (.planned_values.outputs.aws_smsv2_site_listener_ips.value // .prior_state.values.outputs.aws_smsv2_site_listener_ips.value) |
  select(type == "object" and (keys | sort) == ["01", "02", "03"]) |
  select(([.[]] | unique | length) == 3) |
  select(all(.[];
    type == "string" and
    (split(".")) as $octets |
    ($octets | length) == 4 and
    all($octets[]; test("^(0|[1-9][0-9]{0,2})$") and (tonumber <= 255))))' \
  <<<"$DEPLOYMENT_PLAN" 2>/dev/null) || block plan_site_listener_identities_invalid
jq -e '
  [.resource_changes[]? |
    select(.change.actions != ["no-op"] and .change.actions != ["read"]) |
    select(.type | startswith("azurerm_") or startswith("azuread_"))
  ] | length == 0' <<<"$DEPLOYMENT_PLAN" >/dev/null || block azure_changes_present
jq -e '
  [.resource_changes[]? |
    select(.change.actions != ["no-op"] and .change.actions != ["read"]) |
    select((.address | test("^(aws_|module\\.aws_tgw_connect|xcsh_(securemesh_site_v2|site_cloud_init|registration_approval|virtual_site|origin_pool|http_loadbalancer|external_connector|bgp|token)\\.aws|terraform_data\\.aws|xcsh_token\\.ce)")) | not)
  ] | length == 0' <<<"$DEPLOYMENT_PLAN" >/dev/null || block plan_resource_outside_aws_allowlist
EXPECTED_SITES_JSON=$(printf '%s\n' "${EXPECTED_SITES[@]}" | jq -Rsc 'split("\n") | map(select(length > 0)) | sort')
if [ "$PLAN_MODE" = destroy ]; then
  jq -e '[.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"] and .change.actions != ["delete"])] | length == 0' \
    <<<"$DEPLOYMENT_PLAN" >/dev/null || block destroy_plan_contains_non_delete_actions
  jq -e --argjson sites "$EXPECTED_SITES_JSON" '
    [.resource_changes[]? |
      select(.type == "xcsh_securemesh_site_v2" and .name == "aws") |
      select(.change.actions == ["delete"]) |
      select(.change.before.namespace == "system") |
      .change.before.name
    ] | sort == $sites' <<<"$DEPLOYMENT_PLAN" >/dev/null || block task_site_identity_mismatch
else
  DIRECT_SITE_IDENTITIES=$(jq -c '
    [.resource_changes[]? |
      select(.change.actions != ["no-op"] and .change.actions != ["read"]) |
      if .type == "xcsh_securemesh_site_v2" and .name == "aws" then
        select(.change.actions == ["create"] or .change.actions == ["update"] or .change.actions == ["delete", "create"]) |
        select(.change.after.namespace == "system") |
        .change.after.name
      elif .type == "xcsh_token" and .name == "aws" then
        select(.change.actions == ["create"] or .change.actions == ["update"] or .change.actions == ["delete", "create"]) |
        .change.after.site_name
      elif .type == "aws_instance" and .name == "ce" then
        select(.change.actions == ["create"] or .change.actions == ["update"] or .change.actions == ["delete", "create"]) |
        select(.change.after.tags["ves-io-site-name"] | type == "string" and length > 0) |
        .change.after.tags["ves-io-site-name"]
      else
        empty
      end
    ] | unique | sort' <<<"$DEPLOYMENT_PLAN") || block deployment_plan_unreadable
  TGW_BGP_SITE_IDENTITIES=$(jq -c '
    [.resource_changes[]? |
      select(.type == "xcsh_bgp" and .name == "aws_tgw") |
      select(.change.actions != ["no-op"] and .change.actions != ["read"]) |
      select(.change.after.where.site.ref[0].namespace == "system") |
      .change.after.where.site.ref[0].name
    ] | unique | sort' <<<"$DEPLOYMENT_PLAN") || block deployment_plan_unreadable
  KEYED_TASK_SITE_IDENTITIES=$(jq -c '
    (.planned_values.outputs.aws_site_names.value // .prior_state.values.outputs.aws_site_names.value // {}) as $sites |
    [.resource_changes[]? |
      select(
        (.type == "terraform_data" and .name == "aws_tgw_site_route_gate") or
        (.type == "xcsh_registration_approval" and .name == "aws")
      ) |
      select(.change.actions != ["no-op"] and .change.actions != ["read"]) |
      select(.index | type == "string") |
      $sites[.index] |
      select(type == "string" and length > 0)
    ] | unique | sort' <<<"$DEPLOYMENT_PLAN") || block deployment_plan_unreadable
  CONFIGURED_SITE_IDENTITIES=$(jq -c '
    [.resource_changes[]? |
      select(.type == "xcsh_securemesh_site_v2" and .name == "aws") |
      select(.change.after.namespace == "system") |
      .change.after.name
    ] | unique | sort' <<<"$DEPLOYMENT_PLAN") || block deployment_plan_unreadable
  PLAN_BOUND_SITE_IDENTITIES=$(jq -c '
    (.planned_values.outputs.aws_site_names.value // .prior_state.values.outputs.aws_site_names.value // {}) |
    if type == "object" then [.[] | select(type == "string" and length > 0)] | unique | sort else [] end' \
    <<<"$DEPLOYMENT_PLAN") || block deployment_plan_unreadable
  if [ "$DIRECT_SITE_IDENTITIES" = "[]" ]; then
    if [ "$TGW_BGP_SITE_IDENTITIES" != "[]" ]; then
      [ "$TGW_BGP_SITE_IDENTITIES" = "$EXPECTED_SITES_JSON" ] || block task_site_identity_mismatch
    elif [ "$KEYED_TASK_SITE_IDENTITIES" != "[]" ]; then
      [ "$KEYED_TASK_SITE_IDENTITIES" = "$EXPECTED_SITES_JSON" ] || block task_site_identity_mismatch
    elif [ "$PLAN_BOUND_SITE_IDENTITIES" != "[]" ]; then
      [ "$PLAN_BOUND_SITE_IDENTITIES" = "$EXPECTED_SITES_JSON" ] || block task_site_identity_mismatch
    else
      jq -e '[.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])] | length == 0' \
        <<<"$DEPLOYMENT_PLAN" >/dev/null || block task_site_identity_mismatch
      [ "$CONFIGURED_SITE_IDENTITIES" = "$EXPECTED_SITES_JSON" ] || block task_site_identity_mismatch
    fi
  else
    [ "$DIRECT_SITE_IDENTITIES" = "$EXPECTED_SITES_JSON" ] || block task_site_identity_mismatch
  fi
  unset DIRECT_SITE_IDENTITIES TGW_BGP_SITE_IDENTITIES KEYED_TASK_SITE_IDENTITIES CONFIGURED_SITE_IDENTITIES PLAN_BOUND_SITE_IDENTITIES
fi
unset DEPLOYMENT_PLAN
verify_candidate_provider || block candidate_provider_changed
record ready preflight_passed

[ "$EXECUTE_UAT" = true ] || exit 0

command -v curl >/dev/null 2>&1 || block live_uat_dependency_unavailable

verify_mutation_identities() {
  local aws_identity xc_site
  verify_candidate_provider || block candidate_provider_changed
  aws_identity=$(aws sts get-caller-identity --region "$EXPECTED_AWS_REGION" --output json 2>/dev/null) || return 1
  jq -e --arg expected "$EXPECTED_AWS_ACCOUNT" \
    'any(to_entries[]; .key == ("Acc" + "ount") and .value == $expected)' \
    <<<"$aws_identity" >/dev/null || return 1
  xc_site=$(printf 'header = "Authorization: APIToken %s"\n' "$API_TOKEN" |
    curl -fsS --connect-timeout 10 --max-time 30 --config - \
      "${API_URL%/}/api/config/namespaces/system/securemesh_site_v2s/${EXPECTED_SITES[0]}") || return 1
  jq -e --arg site "${EXPECTED_SITES[0]}" --arg namespace system \
    '(.metadata | [.namespace, .name]) == [$namespace, $site]' <<<"$xc_site" >/dev/null || return 1
}

tf() {
  TF_CLI_CONFIG_FILE="$SELECTED_CLI_CONFIG" XCSH_API_TOKEN="$API_TOKEN" \
    terraform -chdir="$TERRAFORM_DIR" "$@"
}

ssm_run() {
  local command_text=$1 command_id status deadline output
  verify_mutation_identities || return 1
  command_id=$(aws ssm send-command \
    --region "$EXPECTED_AWS_REGION" \
    --instance-ids "$WORKLOAD_INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters "$(jq -nc --arg command "$command_text" '{commands: [$command]}')" \
    --query 'Command.CommandId' --output text 2>/dev/null) || return 1
  deadline=$((SECONDS + 300))
  while ((SECONDS < deadline)); do
    status=$(aws ssm get-command-invocation --region "$EXPECTED_AWS_REGION" \
      --command-id "$command_id" --instance-id "$WORKLOAD_INSTANCE_ID" \
      --query Status --output text 2>/dev/null || true)
    case "$status" in
    Success)
      output=$(aws ssm get-command-invocation --region "$EXPECTED_AWS_REGION" \
        --command-id "$command_id" --instance-id "$WORKLOAD_INSTANCE_ID" \
        --query StandardOutputContent --output text 2>/dev/null) || return 1
      printf '%s' "$output"
      return 0
      ;;
    Failed | TimedOut | Cancelled | Cancelling) return 1 ;;
    esac
    sleep 5
  done
  return 1
}

xc_established_peers() {
  local total=0 reachable=0 site response count
  for site in "${EXPECTED_SITES[@]}"; do
    if ! response=$(printf 'header = "Authorization: APIToken %s"\n' "$API_TOKEN" |
      curl -fsS --connect-timeout 10 --max-time 30 --config - \
        "${API_URL%/}/api/operate/namespaces/system/sites/${site}/ver/bgp_peers"); then
      continue
    fi
    reachable=$((reachable + 1))
    count=$(jq '[.. | objects | .protocol_status? | select(type == "string" and ascii_upcase == "ESTABLISHED")] | length' <<<"$response") || return 1
    total=$((total + count))
  done
  [ "$reachable" -gt 0 ] || return 1
  printf '%s' "$total"
}

wait_for_peer_count() {
  local expected=$1 deadline=$((SECONDS + 600)) observed
  while ((SECONDS < deadline)); do
    observed=$(xc_established_peers 2>/dev/null || printf 0)
    [ "$observed" -eq "$expected" ] && return 0
    sleep 10
  done
  return 1
}

nlb_healthy_targets() {
  aws elbv2 describe-target-health --region "$EXPECTED_AWS_REGION" \
    --target-group-arn "$TARGET_GROUP_ARN" --output json 2>/dev/null |
    jq '[.TargetHealthDescriptions[]? | select(.TargetHealth.State == "healthy")] | length'
}

wait_for_target_count() {
  local expected=$1 deadline=$((SECONDS + 600)) observed
  while ((SECONDS < deadline)); do
    observed=$(nlb_healthy_targets 2>/dev/null || printf 0)
    [ "$observed" -eq "$expected" ] && return 0
    sleep 10
  done
  return 1
}

status_plan() {
  local key=$1 software=$2 os=$3 plan_path
  plan_path="${SCRATCH}/status-${key}.tfplan"
  tf plan -refresh-only -input=false -no-color -lock=false \
    -var='aws_upgrade_wait=true' \
    -var="aws_upgrade_observed_sites=[\"${key}\"]" \
    -var="aws_target_software_version=${software}" \
    -var="aws_target_os_version=${os}" \
    -out="$plan_path" >/dev/null || return 1
  tf show -json "$plan_path" | jq -e --arg key "$key" '
    .planned_values.outputs.aws_site_upgrade_status.value[$key] |
    .ready == true and .target_converged == true' >/dev/null
  rm -f "$plan_path"
}

eligibility_plan() {
  local key=$1 plan_path
  plan_path="${SCRATCH}/eligibility-${key}.tfplan"
  tf plan -refresh-only -input=false -no-color -lock=false \
    -var='aws_upgrade_wait=false' \
    -var="aws_upgrade_observed_sites=[\"${key}\"]" \
    -var='aws_target_software_version=crt-20260201-0179' \
    -var='aws_target_os_version=9.2026.17' \
    -out="$plan_path" >/dev/null || return 1
  tf show -json "$plan_path" | jq -e --arg key "$key" '
    .planned_values.outputs.aws_site_upgrade_status.value[$key] |
    .ready == true and .eligible == true and
    .software_available_version == "crt-20260201-0179" and
    .os_available_version == "9.2026.17" and
    (.failed_precheck_names | length) == 0' >/dev/null
  rm -f "$plan_path"
}

invoke_upgrade() {
  local kind=$1 key=$2 plan_path invoke_plan
  plan_path="${SCRATCH}/invoke-${kind}-${key}.tfplan"
  tf plan -input=false -no-color -lock=false -var='aws_upgrade_wait=false' \
    -var="aws_upgrade_observed_sites=[\"${key}\"]" \
    -invoke="xcsh_site_upgrade_${kind}.aws[\"${key}\"]" \
    -out="$plan_path" >/dev/null || return 1
  chmod 600 "$plan_path"
  invoke_plan=$(tf show -json "$plan_path") || return 1
  jq -e '[.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])] | length == 0' \
    <<<"$invoke_plan" >/dev/null || block upgrade_invoke_plan_has_resource_changes
  unset invoke_plan
  verify_mutation_identities || return 1
  tf apply -input=false -no-color -auto-approve "$plan_path" >/dev/null || return 1
  rm -f "$plan_path"
}

WORKLOAD_INSTANCE_ID=$(tf output -raw aws_workload_instance_id 2>/dev/null) || block workload_identity_unavailable
[ -n "$WORKLOAD_INSTANCE_ID" ] || block workload_identity_unavailable
ORIGIN_IP=$(tf output -raw origin_ip 2>/dev/null) || block origin_identity_unavailable
[ -n "$ORIGIN_IP" ] || block origin_identity_unavailable
AWS_VIP=$(tf output -raw aws_vip 2>/dev/null) || block vip_identity_unavailable
[ "$AWS_VIP" = "$PLAN_AWS_VIP" ] || block vip_identity_mismatch
AWS_LB_DOMAIN=$(tf output -raw aws_lb_domain 2>/dev/null) || block loadbalancer_domain_unavailable
[ -n "$AWS_LB_DOMAIN" ] || block loadbalancer_domain_unavailable
SITE_LISTENERS=$(tf output -json aws_smsv2_site_listener_ips 2>/dev/null) || block site_listener_identities_unavailable
[ "$(jq -cS . <<<"$SITE_LISTENERS")" = "$(jq -cS . <<<"$PLAN_SITE_LISTENERS")" ] || block site_listener_identity_mismatch
TARGET_GROUP_ARN=$(tf output -raw aws_smsv2_target_group_arn 2>/dev/null) || block nlb_target_group_identity_unavailable
[ -n "$TARGET_GROUP_ARN" ] || block nlb_target_group_identity_unavailable

TOPOLOGY=$(tf output -json aws_tgw_connect_status 2>/dev/null) || block topology_status_unavailable
jq -e '.runtime_healthy == true and .bgp_converged == true and .interface_count == 6 and .connect_peer_count == 6 and .bgp_session_count == 12' \
  <<<"$TOPOLOGY" >/dev/null || block topology_not_converged
unset TOPOLOGY

[ "$(xc_established_peers)" -eq 12 ] || block twelve_bgp_sessions_unavailable
TGW_ROUTE_TABLE_ID=$(tf output -json 2>/dev/null | jq -r '.aws_tgw_route_table_id.value // empty')
[ -n "$TGW_ROUTE_TABLE_ID" ] || block tgw_route_table_identity_unavailable
while IFS= read -r listener; do
  aws ec2 search-transit-gateway-routes --region "$EXPECTED_AWS_REGION" \
    --transit-gateway-route-table-id "$TGW_ROUTE_TABLE_ID" \
    --filters "Name=route-search.exact-match,Values=${listener}/32" \
    --max-results 20 --output json 2>/dev/null |
    jq -e '[.Routes[]? | select(.State == "active" and .Type == "propagated")] | length >= 1' >/dev/null ||
    block site_listener_tgw_route_unavailable
done < <(jq -r '.[]' <<<"$SITE_LISTENERS")
TARGET_HEALTH=$(aws elbv2 describe-target-health --region "$EXPECTED_AWS_REGION" \
  --target-group-arn "$TARGET_GROUP_ARN" --output json 2>/dev/null) || block nlb_target_health_unavailable
jq -e --argjson listeners "$SITE_LISTENERS" '
  ([.TargetHealthDescriptions[]?.Target.Id] | sort) == ([$listeners[]] | sort) and
  ([.TargetHealthDescriptions[]? | select(.TargetHealth.State == "healthy")] | length) == 3' \
  <<<"$TARGET_HEALTH" >/dev/null || block nlb_target_set_unhealthy
unset TARGET_HEALTH

TRAFFIC_MARKER="mcn-smsv2-uat-${RANDOM}${RANDOM}"
TRAFFIC_COMMAND="umask 077; : > /var/tmp/${TRAFFIC_MARKER}.log; nohup sh -c 'for _ in \$(seq 1 1440); do if curl -fsS --connect-timeout 3 --max-time 10 -H Host:${AWS_LB_DOMAIN} http://${AWS_VIP} >/dev/null; then echo raw_ok; else echo raw_fail; fi; if curl -fsS --retry 2 --retry-all-errors --retry-delay 0 --connect-timeout 3 --max-time 10 -H Host:${AWS_LB_DOMAIN} http://${AWS_VIP} >/dev/null && curl -fsS --connect-timeout 3 --max-time 10 http://${ORIGIN_IP} >/dev/null; then echo ok; else echo fail; fi; sleep 5; done' >/dev/null 2>&1 & echo \$! >/var/tmp/${TRAFFIC_MARKER}.pid"
ssm_run "$TRAFFIC_COMMAND" >/dev/null || block ssm_traffic_start_failed
TRAFFIC_STARTED=true

FAILOVER_INSTANCE_ID=$(tf output -json aws_ce_instance_ids 2>/dev/null | jq -r '.[0] // empty')
[ -n "$FAILOVER_INSTANCE_ID" ] || block failover_identity_unavailable
verify_mutation_identities || block mutation_identity_revalidation_failed
aws ec2 stop-instances --region "$EXPECTED_AWS_REGION" --instance-ids "$FAILOVER_INSTANCE_ID" >/dev/null 2>&1 || block failover_stop_failed
FAILOVER_STOPPED=true
aws ec2 wait instance-stopped --region "$EXPECTED_AWS_REGION" --instance-ids "$FAILOVER_INSTANCE_ID" || block failover_stop_timeout
wait_for_peer_count 8 || block four_sessions_did_not_withdraw
wait_for_target_count 2 || block failed_site_target_did_not_withdraw
verify_mutation_identities || block mutation_identity_revalidation_failed
aws ec2 start-instances --region "$EXPECTED_AWS_REGION" --instance-ids "$FAILOVER_INSTANCE_ID" >/dev/null 2>&1 || block failover_start_failed
aws ec2 wait instance-running --region "$EXPECTED_AWS_REGION" --instance-ids "$FAILOVER_INSTANCE_ID" || block failover_start_timeout
FAILOVER_STOPPED=false
wait_for_peer_count 12 || block twelve_sessions_did_not_reconverge
wait_for_target_count 3 || block three_site_targets_did_not_recover

for key in 01 02 03; do
  status_plan "$key" "crt-20251002-0027" "9.2026.10" || block baseline_version_mismatch
  eligibility_plan "$key" || block upgrade_precheck_or_advertised_target_failed
  invoke_upgrade sw "$key" || block software_upgrade_invoke_failed
  status_plan "$key" "crt-20260201-0179" "9.2026.10" || block software_upgrade_convergence_failed
  invoke_upgrade os "$key" || block os_upgrade_invoke_failed
  status_plan "$key" "crt-20260201-0179" "9.2026.17" || block os_upgrade_convergence_failed
done

TRAFFIC_RESULT=$(ssm_run "pid=\$(cat /var/tmp/${TRAFFIC_MARKER}.pid); kill \"\$pid\" 2>/dev/null || true; sleep 6; awk 'BEGIN{o=0;f=0;ro=0;rf=0} /^ok$/{o++} /^fail$/{f++} /^raw_ok$/{ro++} /^raw_fail$/{rf++} END{printf \"%d %d %d %d\",o,f,ro,rf}' /var/tmp/${TRAFFIC_MARKER}.log; rm -f /var/tmp/${TRAFFIC_MARKER}.pid /var/tmp/${TRAFFIC_MARKER}.log") || block ssm_traffic_result_failed
TRAFFIC_STARTED=false
read -r TRAFFIC_OK TRAFFIC_FAILED RAW_TRAFFIC_OK RAW_TRAFFIC_FAILED <<<"$TRAFFIC_RESULT"
if [ "$TRAFFIC_OK" -lt 2 ] || [ "$TRAFFIC_FAILED" -ne 0 ]; then
  block ssm_traffic_continuity_failed
fi

if tf plan -detailed-exitcode -input=false -no-color -lock=false >/dev/null; then
  :
else
  case $? in
  2) block final_plan_has_changes ;;
  *) block final_plan_failed ;;
  esac
fi

verify_candidate_provider || block candidate_provider_changed

jq -n \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg provider_mode "$PROVIDER_MODE" \
  --arg provider_sha256 "$PROVIDER_SHA256" \
  --argjson traffic_samples "$TRAFFIC_OK" \
  --argjson raw_traffic_samples "$RAW_TRAFFIC_OK" \
  --argjson raw_traffic_failures "$RAW_TRAFFIC_FAILED" \
  '{status:"passed", reason:"aws_smsv2_uat_complete", timestamp:$timestamp,
    provider_mode:$provider_mode,
    provider_sha256:(if $provider_sha256 == "" then null else $provider_sha256 end),
    sites:3, interfaces:6, connect_peers:6, bgp_sessions:12, withdrawn_sessions:4,
    listener_routes:3, healthy_targets_during_failure:2,
    traffic_samples:$traffic_samples, traffic_failures:0,
    raw_transport_samples:($raw_traffic_samples + $raw_traffic_failures),
    raw_transport_failures:$raw_traffic_failures,
    serial_upgrades:3, target_converged:true}' \
  >"$SUMMARY"
chmod 600 "$SUMMARY"
unset API_TOKEN WORKLOAD_INSTANCE_ID FAILOVER_INSTANCE_ID ORIGIN_IP AWS_VIP AWS_LB_DOMAIN SITE_LISTENERS TARGET_GROUP_ARN
printf 'status=passed reason=aws_smsv2_uat_complete\n'
