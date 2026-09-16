#!/usr/bin/env bash
# Inspect only the create operations in one reviewed plan.  A collision is
# never adopted: it is recorded with its owner evidence and blocks before
# Terraform is allowed to mutate AWS or F5 Distributed Cloud.
set -euo pipefail

PLAN_JSON=""
AWS_REGION=""
XC_TENANT=""
CREATOR_ID=""
MANIFEST=""
SCRATCH=""

usage() {
  cat <<'EOF' >&2
Usage: aws-smsv2-owned-collision-preflight.sh \
  --plan-json FILE --aws-region REGION --xc-tenant TENANT \
  --creator-id EMAIL --manifest FILE

The input must be the JSON rendering of the exact saved Terraform plan under
review. The manifest is an evidence record only; it never grants mutation.
EOF
  exit 64
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

while (($#)); do
  case "$1" in
  --plan-json)
    PLAN_JSON=${2:?}
    shift 2
    ;;
  --aws-region)
    AWS_REGION=${2:?}
    shift 2
    ;;
  --xc-tenant)
    XC_TENANT=${2:?}
    shift 2
    ;;
  --creator-id)
    CREATOR_ID=${2:?}
    shift 2
    ;;
  --manifest)
    MANIFEST=${2:?}
    shift 2
    ;;
  -h | --help) usage ;;
  *) usage ;;
  esac
done

for required in PLAN_JSON AWS_REGION XC_TENANT CREATOR_ID MANIFEST; do
  [[ -n ${!required} ]] || die "missing required argument"
done
[[ "$XC_TENANT" == f5-sales-demo ]] || die "xc tenant must be f5-sales-demo"
[[ ${XCSH_API_URL:-} == "https://${XC_TENANT}.console.ves.volterra.io" ]] || die "XCSH_API_URL must match the expected Sales Demo tenant"
[[ -n ${XCSH_API_TOKEN:-} ]] || die "XCSH_API_TOKEN is required"
for command in aws jq sha256sum; do command -v "$command" >/dev/null || die "required command is unavailable: $command"; done

PLAN_JSON=$(realpath "$PLAN_JSON" 2>/dev/null) || die "plan JSON is unavailable"
[[ ! -e "$MANIFEST" ]] || die "manifest already exists; use a new evidence path"
mkdir -p "$(dirname "$MANIFEST")"
MANIFEST=$(cd "$(dirname "$MANIFEST")" && pwd)/$(basename "$MANIFEST")
[[ ! -e "$MANIFEST" ]] || die "manifest already exists; use a new evidence path"
jq -e 'type == "object" and (.resource_changes | type == "array")' "$PLAN_JSON" >/dev/null || die "plan JSON is invalid"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/mcn-owned-collision.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
umask 077
collisions_file="$SCRATCH/collisions.jsonl"
touch "$collisions_file"

append_collision() {
  local engine=$1 type=$2 address=$3 name=$4 namespace=$5 proof=$6 tags=$7
  local ownership_source=${8:-direct_tags}
  jq -nc \
    --arg engine "$engine" --arg type "$type" --arg address "$address" \
    --arg name "$name" --arg namespace "$namespace" --arg proof "$proof" \
    --arg ownership_source "$ownership_source" \
    --argjson tags "$tags" \
    '{engine:$engine,type:$type,address:$address,name:$name,
      namespace:(if $namespace == "" then null else $namespace end),
      ownership:$proof,ownership_source:$ownership_source,expected_tags:$tags}' >>"$collisions_file"
}

aws_not_found() {
  grep -Eq 'InvalidKeyPair\.NotFound|NoSuchEntity|LoadBalancerNotFound|TargetGroupNotFound' "$1"
}

aws_lookup() {
  local out=$1 err=$2
  shift 2
  if aws "$@" --region "$AWS_REGION" --output json >"$out" 2>"$err"; then
    return 0
  fi
  aws_not_found "$err" && return 10
  return 1
}

require_aws_ownership() {
  local expected=$1 actual=$2
  jq -ne --argjson expected "$expected" --argjson actual "$actual" '
    ($expected | type == "object") and
    ([$expected.component, $expected.deployer, $expected.managed_by] | all(type == "string" and length > 0)) and
    ($expected | to_entries | all(.[]; $actual[.key] == .value))' >/dev/null
}

aws_tags_for() {
  local type=$1 response=$2 arn tags_response
  case "$type" in
  aws_key_pair) jq -ec '.KeyPairs[0].Tags // [] | map({key:.Key,value:.Value}) | from_entries' "$response" ;;
  aws_iam_role) jq -ec '.Role.Tags // [] | map({key:.Key,value:.Value}) | from_entries' "$response" ;;
  aws_iam_instance_profile) jq -ec '.InstanceProfile.Tags // [] | map({key:.Key,value:.Value}) | from_entries' "$response" ;;
  aws_lb)
    arn=$(jq -er '.LoadBalancers[0].LoadBalancerArn' "$response") || return 1
    tags_response="$SCRATCH/tags-${RANDOM}.json"
    aws elbv2 describe-tags --resource-arns "$arn" --region "$AWS_REGION" --output json >"$tags_response" 2>/dev/null || return 1
    jq -ec '.TagDescriptions[0].Tags // [] | map({key:.Key,value:.Value}) | from_entries' "$tags_response"
    ;;
  aws_lb_target_group)
    arn=$(jq -er '.TargetGroups[0].TargetGroupArn' "$response") || return 1
    tags_response="$SCRATCH/tags-${RANDOM}.json"
    aws elbv2 describe-tags --resource-arns "$arn" --region "$AWS_REGION" --output json >"$tags_response" 2>/dev/null || return 1
    jq -ec '.TagDescriptions[0].Tags // [] | map({key:.Key,value:.Value}) | from_entries' "$tags_response"
    ;;
  *) return 1 ;;
  esac
}

f5_endpoint() {
  case "$1" in
  xcsh_virtual_site) printf 'virtual_sites' ;;
  xcsh_origin_pool) printf 'origin_pools' ;;
  xcsh_http_loadbalancer) printf 'http_loadbalancers' ;;
  xcsh_securemesh_site_v2) printf 'securemesh_site_v2s' ;;
  xcsh_token) printf 'tokens' ;;
  *) return 1 ;;
  esac
}

f5_namespace_prefix() {
  [[ $1 == xcsh_token ]] && printf 'api/register/namespaces' || printf 'api/config/namespaces'
}

while IFS= read -r item; do
  type=$(jq -er '.type' <<<"$item") || die "plan resource type is invalid"
  address=$(jq -er '.address' <<<"$item") || die "plan resource address is invalid"
  after=$(jq -ec '.after' <<<"$item") || die "plan resource after value is invalid"
  case "$type" in
  aws_key_pair | aws_iam_role | aws_iam_instance_profile | aws_lb | aws_lb_target_group)
    case "$type" in
    aws_key_pair)
      name=$(jq -er '.key_name' <<<"$after")
      lookup=(ec2 describe-key-pairs --key-names "$name")
      ;;
    aws_iam_role)
      name=$(jq -er '.name' <<<"$after")
      lookup=(iam get-role --role-name "$name")
      ;;
    aws_iam_instance_profile)
      name=$(jq -er '.name' <<<"$after")
      lookup=(iam get-instance-profile --instance-profile-name "$name")
      ;;
    aws_lb)
      name=$(jq -er '.name' <<<"$after")
      lookup=(elbv2 describe-load-balancers --names "$name")
      ;;
    aws_lb_target_group)
      name=$(jq -er '.name' <<<"$after")
      lookup=(elbv2 describe-target-groups --names "$name")
      ;;
    esac
    expected_tags=$(jq -ec '.tags // {}' <<<"$after") || die "planned tags are invalid for $address"
    response="$SCRATCH/aws-${RANDOM}.json"
    error="$SCRATCH/aws-${RANDOM}.err"
    if aws_lookup "$response" "$error" "${lookup[@]}"; then
      ownership_source=direct_tags
      if [[ $type == aws_iam_instance_profile && $expected_tags == '{}' ]]; then
        role_name=$(jq -er '.InstanceProfile.Roles | select(length == 1) | .[0].RoleName' "$response") ||
          die "cannot prove the unique role for existing $address"
        expected_tags=$(jq -ec --arg role "$role_name" '
          [.resource_changes[]? |
            select(.type == "aws_iam_role" and .change.after.name == $role) |
            (.change.after.tags // .change.before.tags // {})
          ] | if length == 1 then .[0] else empty end' "$PLAN_JSON") ||
          die "cannot bind existing $address to one planned role"
        role_response="$SCRATCH/aws-role-${RANDOM}.json"
        role_error="$SCRATCH/aws-role-${RANDOM}.err"
        aws_lookup "$role_response" "$role_error" iam get-role --role-name "$role_name" ||
          die "cannot inspect ownership role for existing $address"
        actual_tags=$(aws_tags_for aws_iam_role "$role_response") ||
          die "cannot read ownership role tags for existing $address"
        ownership_source="attached_role:${role_name}"
      else
        actual_tags=$(aws_tags_for "$type" "$response") || die "cannot read tags for existing $address"
      fi
      require_aws_ownership "$expected_tags" "$actual_tags" || die "unowned or ambiguous AWS collision: $address ($name)"
      append_collision aws "$type" "$address" "$name" "" verified "$expected_tags" "$ownership_source"
    else
      status=$?
      [[ $status -eq 10 ]] || die "cannot inspect AWS collision candidate: $address"
    fi
    ;;
  xcsh_virtual_site | xcsh_origin_pool | xcsh_http_loadbalancer | xcsh_securemesh_site_v2 | xcsh_token)
    name=$(jq -er '.name' <<<"$after") || die "planned name is invalid for $address"
    namespace=$(jq -er '.namespace' <<<"$after") || die "planned namespace is invalid for $address"
    endpoint=$(f5_endpoint "$type")
    prefix=$(f5_namespace_prefix "$type")
    body="$SCRATCH/f5-${RANDOM}.json"
    status=$("${CURL_BIN:-curl}" --silent --show-error --output "$body" --write-out '%{http_code}' \
      -H "Authorization: APIToken $XCSH_API_TOKEN" \
      "${XCSH_API_URL%/}/${prefix}/${namespace}/${endpoint}/${name}") || die "cannot inspect F5 collision candidate: $address"
    case "$status" in
    404) ;;
    200)
      jq -e --arg creator "$CREATOR_ID" --arg name "$name" --arg namespace "$namespace" '
            .metadata.name == $name and .metadata.namespace == $namespace and .system_metadata.creator_id == $creator' "$body" >/dev/null ||
        die "unowned or ambiguous F5 collision: $address ($namespace/$name)"
      append_collision f5 "$type" "$address" "$name" "$namespace" verified '{}'
      ;;
    *) die "unexpected F5 response for $address: $status" ;;
    esac
    ;;
  esac
done < <(jq -c '
  .resource_changes[]? |
  select(.change.actions == ["create"]) |
  select(.type == "aws_key_pair" or .type == "aws_iam_role" or
         .type == "aws_iam_instance_profile" or .type == "aws_lb" or
         .type == "aws_lb_target_group" or .type == "xcsh_virtual_site" or
         .type == "xcsh_origin_pool" or .type == "xcsh_http_loadbalancer" or
         .type == "xcsh_securemesh_site_v2" or .type == "xcsh_token") |
  {address, type, after:.change.after}' "$PLAN_JSON")

collisions=$(jq -sc 'sort_by(.engine, .type, .address)' "$collisions_file")
plan_sha256="sha256:$(sha256sum "$PLAN_JSON" | awk '{print $1}')"
if [[ $collisions == '[]' ]]; then status=ready; else status=blocked; fi
jq -n --argjson collisions "$collisions" --arg status "$status" \
  --arg plan_sha256 "$plan_sha256" --arg aws_region "$AWS_REGION" \
  --arg xc_tenant "$XC_TENANT" --arg creator_id "$CREATOR_ID" \
  '{schema_version:1,status:$status,plan_sha256:$plan_sha256,
    aws_region:$aws_region,xc_tenant:$xc_tenant,creator_id:$creator_id,
    collisions:$collisions}' >"$MANIFEST"
chmod 600 "$MANIFEST"

if [[ $status == blocked ]]; then
  printf 'blocked: owned collision(s) recorded in %s; do not apply this plan\n' "$MANIFEST" >&2
  exit 3
fi
printf 'ready: no owned name collision in reviewed plan\n'
