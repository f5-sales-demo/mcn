#!/usr/bin/env bash
# Inspect only the create operations in one reviewed plan.  A collision is
# never adopted: it is recorded with its owner evidence and blocks before
# Terraform is allowed to mutate AWS or F5 Distributed Cloud.
set -euo pipefail

PLAN_JSON=""
AWS_REGION=""
AWS_ACCOUNT_ID=""
XC_TENANT=""
CREATOR_ID=""
COMPONENT=""
DEPLOYMENT_GENERATION=""
RECOVERY_MODE="strict"
MANIFEST=""
SCRATCH=""

usage() {
  cat <<'EOF' >&2
Usage: aws-smsv2-owned-collision-preflight.sh \
  --plan-json FILE --aws-region REGION --aws-account-id ACCOUNT_ID \
  --xc-tenant TENANT --creator-id EMAIL --component COMPONENT \
  --deployment-generation GENERATION [--legacy-unlabelled-recovery] \
  --manifest FILE

The input must be the JSON rendering of the exact saved Terraform plan under
review. The manifest is an evidence record only; it never grants mutation.
Legacy recovery mode is only for adopting a pre-generation deployment through
reviewed Terraform import blocks before its ownership-verified destruction.
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
  --aws-account-id)
    AWS_ACCOUNT_ID=${2:?}
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
  --component)
    COMPONENT=${2:?}
    shift 2
    ;;
  --deployment-generation)
    DEPLOYMENT_GENERATION=${2:?}
    shift 2
    ;;
  --legacy-unlabelled-recovery)
    RECOVERY_MODE="legacy_unlabelled"
    shift
    ;;
  --manifest)
    MANIFEST=${2:?}
    shift 2
    ;;
  -h | --help) usage ;;
  *) usage ;;
  esac
done

for required in PLAN_JSON AWS_REGION AWS_ACCOUNT_ID XC_TENANT CREATOR_ID COMPONENT DEPLOYMENT_GENERATION MANIFEST; do
  [[ -n ${!required} ]] || die "missing required argument"
done
[[ $AWS_ACCOUNT_ID =~ ^[0-9]{12}$ ]] || die "aws account ID must contain exactly 12 digits"
[[ $AWS_REGION =~ ^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$ ]] || die "aws region is invalid"
[[ $COMPONENT =~ ^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$ ]] ||
  die "component must be a 1-32 character DNS-style label"
[[ $DEPLOYMENT_GENERATION =~ ^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$ ]] ||
  die "deployment generation must be a 1-32 character DNS-style label"
[[ "$XC_TENANT" == f5-sales-demo ]] || die "xc tenant must be f5-sales-demo"
[[ ${XCSH_API_URL:-} == "https://${XC_TENANT}.console.ves.volterra.io" ]] || die "XCSH_API_URL must match the expected Sales Demo tenant"
[[ -n ${XCSH_API_TOKEN:-} ]] || die "XCSH_API_TOKEN is required"
for command in aws jq sha256sum; do command -v "$command" >/dev/null || die "required command is unavailable: $command"; done

PLAN_JSON=$(realpath -e "$PLAN_JSON" 2>/dev/null) || die "plan JSON is unavailable"
MANIFEST=$(realpath -m "$MANIFEST")
[[ ! -e "$MANIFEST" ]] || die "manifest already exists; use a new evidence path"
mkdir -p "$(dirname "$MANIFEST")"
[[ ! -e "$MANIFEST" ]] || die "manifest already exists; use a new evidence path"
jq -e 'type == "object" and (.resource_changes | type == "array")' "$PLAN_JSON" >/dev/null || die "plan JSON is invalid"

caller_identity=$(aws sts get-caller-identity --output json 2>/dev/null) || die "cannot verify AWS caller identity"
actual_aws_account_id=$(jq -er '.Account | select(type == "string")' <<<"$caller_identity") ||
  die "AWS caller identity did not include an account ID"
[[ $actual_aws_account_id == "$AWS_ACCOUNT_ID" ]] ||
  die "AWS caller account does not match the expected account"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/mcn-owned-collision.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
umask 077
collisions_file="$SCRATCH/collisions.jsonl"
touch "$collisions_file"

append_aws_collision() {
  local type=$1 address=$2 name=$3 expected_tags=$4 actual_tags=$5 identity=$6
  jq -nc \
    --arg type "$type" --arg address "$address" --arg name "$name" \
    --arg account_id "$AWS_ACCOUNT_ID" --arg region "$AWS_REGION" --arg recovery_mode "$RECOVERY_MODE" \
    --argjson expected_tags "$expected_tags" --argjson observed_tags "$actual_tags" \
    --argjson identity "$identity" \
    '{engine:"aws",type:$type,address:$address,name:$name,namespace:null,
      ownership:"verified",aws_account_id:$account_id,aws_region:$region,
      expected_tags:$expected_tags,observed_tags:$observed_tags,
      resource_uid:$identity.resource_uid,created_at:$identity.created_at,
      creation_evidence:$identity.creation_evidence,
      generation_binding:(if $recovery_mode == "strict" then "observed_metadata"
        else "saved_plan_name_and_legacy_ownership" end)}' >>"$collisions_file"
}

append_f5_collision() {
  local type=$1 address=$2 name=$3 namespace=$4 expected_labels=$5 observed=$6
  jq -nc \
    --arg type "$type" --arg address "$address" --arg name "$name" \
    --arg namespace "$namespace" --arg tenant "$XC_TENANT" --arg recovery_mode "$RECOVERY_MODE" \
    --argjson expected_labels "$expected_labels" --argjson observed "$observed" \
    '{engine:"f5",type:$type,address:$address,name:$name,namespace:$namespace,
      ownership:"verified",xc_tenant:$tenant,
      expected_labels:$expected_labels,observed_labels:$observed.metadata.labels,
      creator_id:$observed.system_metadata.creator_id,
      created_at:$observed.system_metadata.creation_timestamp,
      creation_evidence:"system_metadata.creation_timestamp",
      resource_uid:$observed.system_metadata.uid,
      generation_binding:(if $recovery_mode == "strict" then "observed_metadata"
        else "saved_plan_name_and_legacy_ownership" end)}' >>"$collisions_file"
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
  local expected=$1 actual=$2 name=$3
  jq -ne --arg component "$COMPONENT" --argjson expected "$expected" --argjson actual "$actual" '
    ($expected | type == "object") and
    ([$expected.component, $expected.deployer, $expected.managed_by] |
      all(type == "string" and length > 0)) and
    $expected.component == $component and
    ($expected | to_entries | all(.[]; $actual[.key] == .value))' >/dev/null
  if [[ $RECOVERY_MODE == strict ]]; then
    jq -ne --arg generation "$DEPLOYMENT_GENERATION" --argjson expected "$expected" --argjson actual "$actual" '
      $expected.deployment_generation == $generation and
      $actual.deployment_generation == $generation' >/dev/null
  else
    [[ $name == "$COMPONENT-$DEPLOYMENT_GENERATION-"* ]] || return 1
    jq -ne --arg generation "$DEPLOYMENT_GENERATION" --argjson expected "$expected" --argjson actual "$actual" '
      (($expected.deployment_generation? // $generation) == $generation) and
      (($actual.deployment_generation? // $generation) == $generation)' >/dev/null
  fi
}

aws_identity_for() {
  local type=$1 response=$2
  case "$type" in
  aws_key_pair)
    jq -ec '{resource_uid:.KeyPairs[0].KeyPairId,created_at:(.KeyPairs[0].CreateTime // null),
      creation_evidence:(if .KeyPairs[0].CreateTime then "ec2.describe-key-pairs.CreateTime" else "not_exposed" end)}' "$response"
    ;;
  aws_iam_role)
    jq -ec '{resource_uid:.Role.RoleId,created_at:(.Role.CreateDate // null),
      creation_evidence:(if .Role.CreateDate then "iam.get-role.CreateDate" else "not_exposed" end)}' "$response"
    ;;
  aws_iam_instance_profile)
    jq -ec '{resource_uid:.InstanceProfile.InstanceProfileId,created_at:(.InstanceProfile.CreateDate // null),
      creation_evidence:(if .InstanceProfile.CreateDate then "iam.get-instance-profile.CreateDate" else "not_exposed" end)}' "$response"
    ;;
  aws_lb)
    jq -ec '{resource_uid:.LoadBalancers[0].LoadBalancerArn,created_at:(.LoadBalancers[0].CreatedTime // null),
      creation_evidence:(if .LoadBalancers[0].CreatedTime then "elbv2.describe-load-balancers.CreatedTime" else "not_exposed" end)}' "$response"
    ;;
  aws_lb_target_group)
    jq -ec '{resource_uid:.TargetGroups[0].TargetGroupArn,created_at:null,
      creation_evidence:"not_exposed_by_elbv2_describe_target_groups"}' "$response"
    ;;
  aws_eip)
    jq -ec '{resource_uid:.Addresses[0].AllocationId,created_at:null,
      creation_evidence:"not_exposed_by_ec2_describe_addresses"}' "$response"
    ;;
  *) return 1 ;;
  esac
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
  aws_eip) jq -ec '.Addresses[0].Tags // [] | map({key:.Key,value:.Value}) | from_entries' "$response" ;;
  *) return 1 ;;
  esac
}

f5_endpoint() {
  case "$1" in
  xcsh_virtual_site) printf 'virtual_sites' ;;
  xcsh_origin_pool) printf 'origin_pools' ;;
  xcsh_http_loadbalancer) printf 'http_loadbalancers' ;;
  xcsh_token) printf 'tokens' ;;
  xcsh_securemesh_site_v2) printf 'securemesh_site_v2s' ;;
  xcsh_bgp) printf 'bgps' ;;
  xcsh_external_connector) printf 'external_connectors' ;;
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
  expected_tags=""
  case "$type" in
  aws_key_pair | aws_iam_role | aws_iam_instance_profile | aws_lb | aws_lb_target_group | aws_eip)
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
    aws_eip)
      # Elastic IPs have allocation IDs only after creation. The exact
      # deployment tag tuple is therefore their planned identity; make that
      # binding explicit in the evidence name for legacy-recovery validation.
      name="${COMPONENT}-${DEPLOYMENT_GENERATION}-eip-${address}"
      expected_tags=$(jq -ec '.tags // {}' <<<"$after") || die "planned tags are invalid for $address"
      mapfile -t eip_tag_filters < <(jq -r 'to_entries[] | "Name=tag:\(.key),Values=\(.value)"' <<<"$expected_tags")
      ((${#eip_tag_filters[@]} > 0)) || die "planned tags are incomplete for $address"
      lookup=(ec2 describe-addresses --filters "${eip_tag_filters[@]}")
      ;;
    esac
    expected_tags=${expected_tags:-$(jq -ec '.tags // {}' <<<"$after")} || die "planned tags are invalid for $address"
    response="$SCRATCH/aws-${RANDOM}.json"
    error="$SCRATCH/aws-${RANDOM}.err"
    if aws_lookup "$response" "$error" "${lookup[@]}"; then
      if [[ $type == aws_eip ]]; then
        eip_matches=$(jq -er '.Addresses | length' "$response") || die "cannot read existing EIP candidates for $address"
        [[ $eip_matches -eq 0 ]] && continue
        [[ $eip_matches -eq 1 ]] || die "unowned or ambiguous AWS collision: $address (multiple Elastic IPs match the planned ownership tags)"
      fi
      actual_tags=$(aws_tags_for "$type" "$response") || die "cannot read tags for existing $address"
      require_aws_ownership "$expected_tags" "$actual_tags" "$name" || die "unowned or ambiguous AWS collision: $address ($name)"
      identity=$(aws_identity_for "$type" "$response") || die "cannot read provider identity for existing $address"
      jq -e '.resource_uid | type == "string" and length > 0' <<<"$identity" >/dev/null ||
        die "provider identity is unavailable for existing $address"
      append_aws_collision "$type" "$address" "$name" "$expected_tags" "$actual_tags" "$identity"
    else
      status=$?
      [[ $status -eq 10 ]] || die "cannot inspect AWS collision candidate: $address"
    fi
    ;;
  xcsh_virtual_site | xcsh_origin_pool | xcsh_http_loadbalancer | xcsh_token | xcsh_securemesh_site_v2 | xcsh_bgp | xcsh_external_connector)
    name=$(jq -er '.name' <<<"$after") || die "planned name is invalid for $address"
    namespace=$(jq -er '.namespace' <<<"$after") || die "planned namespace is invalid for $address"
    expected_labels=$(jq -ec '.labels // {}' <<<"$after") || die "planned labels are invalid for $address"
    if [[ $RECOVERY_MODE == strict ]]; then
      jq -e --arg generation "$DEPLOYMENT_GENERATION" '
        .["mcn-deployment-generation"] == $generation' <<<"$expected_labels" >/dev/null ||
        die "planned deployment generation label is missing or mismatched for $address"
    else
      jq -e --arg generation "$DEPLOYMENT_GENERATION" '
        ((.["mcn-deployment-generation"]? // $generation) == $generation)' <<<"$expected_labels" >/dev/null ||
        die "legacy planned generation label conflicts with the recovery generation for $address"
    fi
    endpoint=$(f5_endpoint "$type")
    prefix=$(f5_namespace_prefix "$type")
    body="$SCRATCH/f5-${RANDOM}.json"
    status=$("${CURL_BIN:-curl}" --silent --show-error --output "$body" --write-out '%{http_code}' \
      -H "Authorization: APIToken $XCSH_API_TOKEN" \
      "${XCSH_API_URL%/}/${prefix}/${namespace}/${endpoint}/${name}") || die "cannot inspect F5 collision candidate: $address"
    case "$status" in
    404) ;;
    200)
      if [[ $RECOVERY_MODE == legacy_unlabelled && $name != "$COMPONENT-$DEPLOYMENT_GENERATION-"* ]]; then
        die "legacy recovery name is not bound to the expected component and generation: $address"
      fi
      jq -e --arg creator "$CREATOR_ID" --arg name "$name" --arg namespace "$namespace" \
        --arg generation "$DEPLOYMENT_GENERATION" --arg recovery_mode "$RECOVERY_MODE" '
            .metadata.name == $name and .metadata.namespace == $namespace and
            (if $recovery_mode == "strict" then
              .metadata.labels["mcn-deployment-generation"] == $generation
            else
              ((.metadata.labels["mcn-deployment-generation"]? // $generation) == $generation)
            end) and
            .system_metadata.creator_id == $creator and
            (.system_metadata.uid | type == "string" and length > 0) and
            (.system_metadata.creation_timestamp | type == "string" and length > 0)' "$body" >/dev/null ||
        die "unowned or ambiguous F5 collision: $address ($namespace/$name)"
      observed=$(jq -ec '{metadata:{labels:.metadata.labels},system_metadata:{
        creator_id:.system_metadata.creator_id,creation_timestamp:.system_metadata.creation_timestamp,
        uid:.system_metadata.uid}}' "$body") || die "cannot normalize F5 ownership evidence for $address"
      append_f5_collision "$type" "$address" "$name" "$namespace" "$expected_labels" "$observed"
      ;;
    *) die "unexpected F5 response for $address: $status" ;;
    esac
    ;;
  *) die "preflight has no complete ownership adapter for planned resource type: $type ($address)" ;;
  esac
done < <(jq -c '
  .resource_changes[]? |
  select(.change.actions == ["create"]) |
  {address, type, after:.change.after}' "$PLAN_JSON")

collisions=$(jq -sc 'sort_by(.engine, .type, .address)' "$collisions_file")
plan_sha256="sha256:$(sha256sum "$PLAN_JSON" | awk '{print $1}')"
inventory_captured_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
if [[ $collisions == '[]' ]]; then status=ready; else status=blocked; fi
jq -n --argjson collisions "$collisions" --arg status "$status" \
  --argjson caller_identity "$caller_identity" --arg inventory_captured_at "$inventory_captured_at" \
  --arg plan_sha256 "$plan_sha256" --arg aws_region "$AWS_REGION" \
  --arg aws_account_id "$AWS_ACCOUNT_ID" --arg deployment_generation "$DEPLOYMENT_GENERATION" \
  --arg xc_tenant "$XC_TENANT" --arg creator_id "$CREATOR_ID" --arg component "$COMPONENT" \
  --arg recovery_mode "$RECOVERY_MODE" \
  '{schema_version:2,status:$status,plan_sha256:$plan_sha256,
    aws_region:$aws_region,aws_account_id:$aws_account_id,
    aws_caller_arn:($caller_identity.Arn // null),
    aws_caller_user_id:($caller_identity.UserId // null),inventory_captured_at:$inventory_captured_at,
    xc_tenant:$xc_tenant,creator_id:$creator_id,component:$component,
    deployment_generation:$deployment_generation,recovery_mode:$recovery_mode,
    collisions:$collisions}' >"$MANIFEST"
chmod 600 "$MANIFEST"

if [[ $status == blocked ]]; then
  printf 'blocked: owned collision(s) recorded in %s; do not apply this plan\n' "$MANIFEST" >&2
  exit 3
fi
printf 'ready: no owned name collision in reviewed plan\n'
