#!/usr/bin/env bash
# Non-mutating identity and capability gate for an AWS SMSv2 live apply.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
EVIDENCE_DIR=""
TERRAFORM_DIR="${REPO_ROOT}/terraform"
PLAN_FILE=""
EXPECTED_AWS_ACCOUNT=""
EXPECTED_AWS_REGION=""
EXPECTED_AZURE_SUBSCRIPTION=""
EXPECTED_BACKEND_RESOURCE_GROUP=""
EXPECTED_BACKEND_STORAGE_ACCOUNT=""
EXPECTED_BACKEND_CONTAINER=""
EXPECTED_BACKEND_KEY=""
EXPECTED_XC_TENANT=""
EXPECTED_SITE=""
XC_CONTEXT="f5-sales-demo"
SUMMARY=""
SCRATCH=""

usage() {
  cat <<'EOF'
Usage: aws-smsv2-uat-preflight.sh [options]

Required options:
  --evidence-dir PATH
  --plan-file PATH
  --expected-aws-account ID
  --expected-aws-region REGION
  --expected-azure-subscription ID
  --expected-backend-resource-group NAME
  --expected-backend-storage-account NAME
  --expected-backend-container NAME
  --expected-backend-key KEY
  --expected-xc-tenant NAME
  --expected-site NAME

Optional:
  --terraform-dir PATH   Defaults to the repository terraform directory.
  --xc-context NAME      Defaults to f5-sales-demo when XC environment values are absent.
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
    '{status: $status, reason: $reason, timestamp: $timestamp}' >"$SUMMARY"
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
  --expected-aws-account)
    EXPECTED_AWS_ACCOUNT=${2:?}
    shift 2
    ;;
  --expected-aws-region)
    EXPECTED_AWS_REGION=${2:?}
    shift 2
    ;;
  --expected-azure-subscription)
    EXPECTED_AZURE_SUBSCRIPTION=${2:?}
    shift 2
    ;;
  --expected-backend-resource-group)
    EXPECTED_BACKEND_RESOURCE_GROUP=${2:?}
    shift 2
    ;;
  --expected-backend-storage-account)
    EXPECTED_BACKEND_STORAGE_ACCOUNT=${2:?}
    shift 2
    ;;
  --expected-backend-container)
    EXPECTED_BACKEND_CONTAINER=${2:?}
    shift 2
    ;;
  --expected-backend-key)
    EXPECTED_BACKEND_KEY=${2:?}
    shift 2
    ;;
  --expected-xc-tenant)
    EXPECTED_XC_TENANT=${2:?}
    shift 2
    ;;
  --expected-site)
    EXPECTED_SITE=${2:?}
    shift 2
    ;;
  --xc-context)
    XC_CONTEXT=${2:?}
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument" ;;
  esac
done

for value in EVIDENCE_DIR PLAN_FILE EXPECTED_AWS_ACCOUNT EXPECTED_AWS_REGION \
  EXPECTED_AZURE_SUBSCRIPTION EXPECTED_BACKEND_RESOURCE_GROUP \
  EXPECTED_BACKEND_STORAGE_ACCOUNT EXPECTED_BACKEND_CONTAINER \
  EXPECTED_BACKEND_KEY EXPECTED_XC_TENANT EXPECTED_SITE; do
  [ -n "${!value}" ] || die "missing required preflight argument"
done

for command_name in terraform jq aws az realpath; do
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
trap 'rm -rf "$SCRATCH"' EXIT

API_URL=${XCSH_API_URL:-}
API_TOKEN=${XCSH_API_TOKEN:-}
if [ -z "$API_URL" ] || [ -z "$API_TOKEN" ]; then
  CONTEXT_FILE="${HOME}/.config/xcsh/contexts/${XC_CONTEXT}.json"
  [ -f "$CONTEXT_FILE" ] || block xc_credentials_unavailable
  [ -n "$API_URL" ] || API_URL=$(jq -r '.apiUrl // empty' "$CONTEXT_FILE")
  [ -n "$API_TOKEN" ] || API_TOKEN=$(jq -r '.apiToken // empty' "$CONTEXT_FILE")
fi
[ -n "$API_URL" ] && [ -n "$API_TOKEN" ] || block xc_credentials_unavailable
[ "${API_URL%/}" = "https://${EXPECTED_XC_TENANT}.console.ves.volterra.io" ] || block xc_tenant_mismatch

cat >"${SCRATCH}/main.tf" <<'TF'
terraform {
  required_providers {
    xcsh = {
      source  = "f5-sales-demo/xcsh"
      version = "= 7.0.0"
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

TF_VAR_api_url="$API_URL" XCSH_API_TOKEN="$API_TOKEN" \
  terraform -chdir="$SCRATCH" init -backend=false -input=false -no-color >/dev/null 2>&1 || block v7_provider_install_failed
PROVIDER_VERSION=$(terraform -chdir="$SCRATCH" version -json 2>/dev/null |
  jq -r '.provider_selections["registry.terraform.io/f5-sales-demo/xcsh"] // empty')
[ "$PROVIDER_VERSION" = "7.0.0" ] || block v7_provider_resolution_mismatch
TF_VAR_api_url="$API_URL" XCSH_API_TOKEN="$API_TOKEN" \
  terraform -chdir="$SCRATCH" plan -refresh=false -input=false -lock=false \
  -out=contract.tfplan -no-color >/dev/null 2>&1 || block v7_contract_query_failed
CONTRACT=$(terraform -chdir="$SCRATCH" show -json contract.tfplan 2>/dev/null |
  jq -c '.planned_values.outputs.contract.value // empty')
[ -n "$CONTRACT" ] || block v7_contract_query_failed

EXPECTED_API_COMMIT="8a48ca67ad""9fc23174d0""86c0d63a27""83e531044b"
jq -e --arg api_commit "$EXPECTED_API_COMMIT" '
  .contract_id == "f5xc-ce-automation/v3" and
  .contract_version == "6.0.0" and
  .api_release_tag == "v6.0.0" and
  .api_release_commit == $api_commit and
  .telemetry_schema_id == "f5xc-smsv2-aws-tgw-telemetry/v2"' <<<"$CONTRACT" >/dev/null || block v7_contract_identity_mismatch
jq -e '
  (.f5xc_authorities | sort) == (["smsv2_configuration", "runtime_health", "bgp_peers", "bgp_routes", "simplified_routes"] | sort) and
  (.aws_authorities | sort) == (["eni", "transit_gateway", "transit_gateway_connect", "gre_endpoints", "bgp_inside_cidrs", "autonomous_system_numbers"] | sort)' \
  <<<"$CONTRACT" >/dev/null || block v7_authority_mismatch
jq -e '
  (.capabilities | keys | sort) == (["aws_ce_create", "runtime_status", "tgw_connect"] | sort) and
  ([.capabilities[]] | all(. == "available"))' <<<"$CONTRACT" >/dev/null || block v7_capabilities_unavailable

unset API_TOKEN CONTRACT

PLAN_FILE=$(realpath -m "$PLAN_FILE")
[ -f "$PLAN_FILE" ] || block deployment_plan_unavailable

AWS_REGION_SELECTED=${AWS_REGION:-${AWS_DEFAULT_REGION:-}}
[ "$AWS_REGION_SELECTED" = "$EXPECTED_AWS_REGION" ] || block aws_region_mismatch
AWS_IDENTITY=$(aws sts get-caller-identity --region "$EXPECTED_AWS_REGION" --output json 2>/dev/null) || block aws_identity_unavailable
jq -e --arg expected "$EXPECTED_AWS_ACCOUNT" '.Account == $expected' <<<"$AWS_IDENTITY" >/dev/null || block aws_account_mismatch
unset AWS_IDENTITY

AZURE_IDENTITY=$(az account show --output json 2>/dev/null) || block azure_identity_unavailable
jq -e --arg expected "$EXPECTED_AZURE_SUBSCRIPTION" '.id == $expected' <<<"$AZURE_IDENTITY" >/dev/null || block azure_subscription_mismatch
unset AZURE_IDENTITY

BACKEND_STATE="${TERRAFORM_DIR}/.terraform/terraform.tfstate"
[ -f "$BACKEND_STATE" ] || block azure_backend_unavailable
jq -e \
  --arg subscription "$EXPECTED_AZURE_SUBSCRIPTION" \
  --arg resource_group "$EXPECTED_BACKEND_RESOURCE_GROUP" \
  --arg storage_account "$EXPECTED_BACKEND_STORAGE_ACCOUNT" \
  --arg container "$EXPECTED_BACKEND_CONTAINER" \
  --arg key "$EXPECTED_BACKEND_KEY" \
  '.backend.type == "azurerm" and
   .backend.config.subscription_id == $subscription and
   .backend.config.resource_group_name == $resource_group and
   .backend.config.storage_account_name == $storage_account and
   .backend.config.container_name == $container and
   .backend.config.key == $key' "$BACKEND_STATE" >/dev/null || block azure_backend_mismatch

DEPLOYMENT_PLAN=$(terraform -chdir="$TERRAFORM_DIR" show -json "$PLAN_FILE" 2>/dev/null) || block deployment_plan_unreadable
jq -e --arg site "$EXPECTED_SITE" '
  [.resource_changes[]? |
    select(.address == "xcsh_securemesh_site_v2.aws[0]") |
    select(.change.actions == ["create"] or .change.actions == ["no-op"] or .change.actions == ["update"]) |
    select(.change.after.name == $site and .change.after.namespace == "system")
  ] | length == 1' <<<"$DEPLOYMENT_PLAN" >/dev/null || block task_site_identity_mismatch
unset DEPLOYMENT_PLAN
record ready preflight_passed
