#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_block() {
  local resource=$1
  local source_file=$2
  local block
  [[ -f $source_file ]] || fail "Azure-free AWS root is missing ${source_file##*/}"
  block=$(sed -n "/resource \\\"aws_iam_instance_profile\\\" \\\"${resource}\\\" {/,/^}/p" "$source_file")
  grep -Eq '^[[:space:]]*tags[[:space:]]*=[[:space:]]*local\.tags$' <<<"$block" ||
    fail "aws_iam_instance_profile.${resource} must carry the standard ownership tags"
}

require_block ce "$repo_root/terraform/aws/aws_ce.tf"
require_block workload "$repo_root/terraform/aws/aws_vpc.tf"

require_tgw_module_ownership_tags() {
  local source_file=$1
  local block
  block=$(sed -n '/module \"aws_tgw_connect\" {/,/^}/p' "$source_file")
  grep -Eq '^[[:space:]]*ownership_tags[[:space:]]*=[[:space:]]*local\.tags$' <<<"$block" ||
    fail "aws_tgw_connect in ${source_file#$repo_root/} must pass immutable ownership tags"
}

require_tgw_module_ownership_tags "$repo_root/terraform/aws/aws_tgw_connect.tf"
require_tgw_module_ownership_tags "$repo_root/terraform/aws_tgw_connect.tf"

# The tenant guard must be a dependency of planned object metadata. An unused
# data source is not evaluated by Terraform, which would let a wrong tenant
# reach the provider before its postcondition could reject the plan.
locals_file="$repo_root/terraform/aws/locals.tf"
grep -Eq "^[[:space:]]*xc_tenant[[:space:]]*=[[:space:]]*data\\.external\\.xc_env_tenant\\.result\\.tenant$" "$locals_file" ||
  fail "AWS root must bind the active XC tenant guard into shared metadata"
grep -Eq "^[[:space:]]*xc_tenant[[:space:]]*=[[:space:]]*local\\.xc_tenant$" "$locals_file" ||
  fail "AWS ownership tags must carry the evaluated XC tenant"
grep -Fq '"mcn-xc-tenant"             = local.xc_tenant' "$locals_file" ||
  fail "XC labels must carry the evaluated XC tenant"

printf 'PASS: AWS ownership metadata evaluates and carries the active XC tenant guard\n'
