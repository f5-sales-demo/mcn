#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
recovery_root="$repo_root/terraform/recovery/aws-smsv2-orphans"
verifier="$repo_root/scripts/verify-aws-smsv2-orphan-recovery-plan.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for required in versions.tf backend.tf providers.tf variables.tf locals.tf resources.tf imports.tf; do
  [[ -f "$recovery_root/$required" ]] || fail "recovery root is missing $required"
done
[[ -x "$verifier" ]] || fail "recovery plan verifier is not executable"

resource_count=$(grep -hEc '^resource "' "$recovery_root"/*.tf | awk '{ count += $1 } END { print count + 0 }')
import_count=$(grep -hEc '^import \{' "$recovery_root"/*.tf | awk '{ count += $1 } END { print count + 0 }')
ignore_count=$(grep -hEc '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*all$' "$recovery_root"/*.tf | awk '{ count += $1 } END { print count + 0 }')
data_lb_count=$(grep -hEc '^data "aws_lb" "recovery"' "$recovery_root"/*.tf | awk '{ count += $1 } END { print count + 0 }')
data_target_group_count=$(grep -hEc '^data "aws_lb_target_group" "recovery"' "$recovery_root"/*.tf | awk '{ count += $1 } END { print count + 0 }')
[[ $resource_count -eq 12 ]] || fail "recovery root must declare exactly twelve supported resource types"
[[ $import_count -eq 12 ]] || fail "recovery root must declare exactly twelve configuration-driven import blocks"
[[ $ignore_count -eq 12 ]] || fail "every recovery resource must ignore drift during adoption"
grep -Eq 'aws_eip' "$recovery_root/imports.tf" || fail "recovery must import verified legacy EIPs"
grep -Eq 'aws_eip' "$recovery_root/resources.tf" || fail "recovery must configure verified legacy EIPs"
[[ $data_lb_count -eq 1 ]] || fail "recovery must read the existing load-balancer shape for an import-only plan"
grep -Eq 'aws_instance' "$recovery_root/imports.tf" || fail "recovery must import EIP-owning instances"
grep -Eq 'aws_instance' "$recovery_root/resources.tf" || fail "recovery must configure EIP-owning instances"
grep -Eq 'attached_eip_dependency_closure' "$recovery_root/locals.tf" ||
  fail "recovery must reject an attached EIP without its owning instance"
grep -Eq 'depends_on[[:space:]]*=[[:space:]]*\[aws_eip\.recovery\]' "$recovery_root/resources.tf" ||
[[ $data_target_group_count -eq 1 ]] || fail "recovery must read the existing target-group shape for an import-only plan"
grep -Eq 'subnets[[:space:]]*=[[:space:]]*data\.aws_lb\.recovery' "$recovery_root/resources.tf" ||
  fail "recovery load balancer must use its observed subnets"
grep -Eq 'vpc_id[[:space:]]*=[[:space:]]*data\.aws_lb_target_group\.recovery' "$recovery_root/resources.tf" ||
  fail "recovery target group must use its observed VPC"
grep -Eq 'discovered_site_labels' "$recovery_root/locals.tf" ||
  fail "recovery must identify F5-discovered site labels"
grep -Eq '!contains\(local\.discovered_site_labels, key\)' "$recovery_root/resources.tf" ||
  fail "recovery must exclude F5-discovered labels from securemesh configuration"
if grep -R --exclude-dir=.terraform -En 'terraform[[:space:]]+import|local-exec|curl.+DELETE|aws.+delete-' "$recovery_root" "$verifier"; then
  fail "recovery implementation contains an imperative mutation path"
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
manifest="$scratch/manifest.json"
plan="$scratch/plan.json"
receipt="$scratch/receipt.json"

jq -n '{
  schema_version:2,status:"blocked",recovery_mode:"legacy_unlabelled",
  plan_sha256:"sha256:source-plan",aws_account_id:"123456789012",aws_region:"us-east-1",
  xc_tenant:"f5-sales-demo",creator_id:"tester@example.test",component:"mcn-ce-ha",
  deployment_generation:"gen-01",inventory_captured_at:"2026-09-16T12:00:00Z",
  collisions:[
    {engine:"aws",type:"aws_key_pair",address:"aws_key_pair.ce[0]",name:"mcn-ce-ha-gen-01-key",
     namespace:null,ownership:"verified",resource_uid:"key-0123456789abcdef0",
     created_at:"2026-09-16T12:00:00Z",creation_evidence:"ec2.describe-key-pairs.CreateTime",
     generation_binding:"saved_plan_name_and_legacy_ownership",observed_tags:{component:"mcn-ce-ha"}},
    {engine:"aws",type:"aws_eip",address:"aws_eip.ce[0]",name:"mcn-ce-ha-aws-ce-1-eip",
     namespace:null,ownership:"verified",resource_uid:"eipalloc-0123456789abcdef0",
     created_at:"2026-09-16T12:00:00Z",creation_evidence:"ec2.describe-addresses.AllocationId",
     generation_binding:"saved_plan_name_and_legacy_ownership",observed_tags:{component:"mcn-ce-ha",managed_by:"terraform"}},
    {engine:"f5",type:"xcsh_token",address:"xcsh_token.aws[\"01\"]",name:"mcn-ce-ha-gen-01-token",
     namespace:"system",ownership:"verified",resource_uid:"11111111-1111-1111-1111-111111111111",
     created_at:"2026-09-16T12:00:00Z",creation_evidence:"system_metadata.creation_timestamp",
     generation_binding:"saved_plan_name_and_legacy_ownership",observed_labels:{}}
  ]
}' >"$manifest"

jq -n '{format_version:"1.2",terraform_version:"1.16.3",
  configuration:{provider_config:{xcsh:{full_name:"registry.terraform.io/f5-sales-demo/xcsh",version_constraint:"9.2.2"}}},
  resource_changes:[
  {address:"aws_key_pair.recovery[\"aws_key_pair.ce[0]\"]",type:"aws_key_pair",
   change:{actions:["no-op"],importing:{id:"mcn-ce-ha-gen-01-key"}}},
  {address:"aws_eip.recovery[\"aws_eip.ce[0]\"]",type:"aws_eip",
   change:{actions:["no-op"],importing:{id:"eipalloc-0123456789abcdef0"}}},
  {address:"xcsh_token.recovery[\"xcsh_token.aws[\\\"01\\\"]\"]",type:"xcsh_token",
   change:{actions:["no-op"],importing:{id:"system/mcn-ce-ha-gen-01-token"}}}
]}' >"$plan"

"$verifier" --mode import --plan-json "$plan" --manifest "$manifest" --receipt "$receipt"
jq -e '.schema_version == 1 and .status == "ready" and .mode == "import" and .resource_count == 3 and
  (.plan_sha256 | startswith("sha256:")) and (.manifest_sha256 | startswith("sha256:"))' \
  "$receipt" >/dev/null || fail "recovery receipt does not bind the exact plan and manifest"

mutation_plan="$scratch/mutation-plan.json"
jq '(.resource_changes[0].change.actions) = ["create"] | del(.resource_changes[0].change.importing)' \
  "$plan" >"$mutation_plan"
if "$verifier" --mode import --plan-json "$mutation_plan" --manifest "$manifest" \
  --receipt "$scratch/mutation-receipt.json" >/dev/null 2>&1; then
  fail "recovery verifier accepted a create action"
fi

mismatch_plan="$scratch/mismatch-plan.json"
jq '(.resource_changes[1].change.importing.id) = "system/wrong-token"' "$plan" >"$mismatch_plan"
if "$verifier" --mode import --plan-json "$mismatch_plan" --manifest "$manifest" \
  --receipt "$scratch/mismatch-receipt.json" >/dev/null 2>&1; then
  fail "recovery verifier accepted an import ID mismatch"
fi

attached_eip_manifest="$scratch/attached-eip-without-instance.json"
jq '(.collisions[] | select(.type == "aws_eip")).attachment_instance_id = "i-0123456789abcdef0"' \
  "$manifest" >"$attached_eip_manifest"
if "$verifier" --mode import --plan-json "$plan" --manifest "$attached_eip_manifest" \
  --receipt "$scratch/attached-eip-receipt.json" >/dev/null 2>&1; then
  fail "recovery verifier accepted an attached EIP without its owning instance"
fi

destroy_plan="$scratch/destroy-plan.json"
destroy_receipt="$scratch/destroy-receipt.json"
jq -n '{format_version:"1.2",terraform_version:"1.16.3",
  configuration:{provider_config:{xcsh:{full_name:"registry.terraform.io/f5-sales-demo/xcsh",version_constraint:"9.2.2"}}},
  resource_changes:[
    {address:"aws_key_pair.recovery[\"aws_key_pair.ce[0]\"]",type:"aws_key_pair",
     change:{actions:["delete"],before:{id:"mcn-ce-ha-gen-01-key",key_name:"mcn-ce-ha-gen-01-key"},after:null}},
    {address:"aws_eip.recovery[\"aws_eip.ce[0]\"]",type:"aws_eip",
     change:{actions:["delete"],before:{id:"eipalloc-0123456789abcdef0",allocation_id:"eipalloc-0123456789abcdef0"},after:null}},
    {address:"xcsh_token.recovery[\"xcsh_token.aws[\\\"01\\\"]\"]",type:"xcsh_token",
     change:{actions:["delete"],before:{id:"mcn-ce-ha-gen-01-token",name:"mcn-ce-ha-gen-01-token"},after:null}}
  ]}' >"$destroy_plan"
"$verifier" --mode destroy --plan-json "$destroy_plan" --manifest "$manifest" \
  --receipt "$destroy_receipt"
jq -e '.status == "ready" and .mode == "destroy" and .resource_count == 3 and
  .allowed_actions == ["delete"]' "$destroy_receipt" >/dev/null ||
  fail "destroy receipt does not prove an exact manifest-bound deletion"

printf 'PASS: orphan recovery is configuration-driven, import-only and plan-bound\n'
