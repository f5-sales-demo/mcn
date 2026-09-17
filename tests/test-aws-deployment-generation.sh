#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
aws_root="$repo_root/terraform/aws"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_text() {
  local file=$1 text=$2
  grep -Fq -- "$text" "$file" || fail "${file#"$repo_root"/} is missing: $text"
}

variables="$aws_root/variables.tf"
locals_file="$aws_root/locals.tf"
tgw="$aws_root/aws_tgw_connect.tf"
xc="$aws_root/aws_xc.tf"

require_text "$variables" 'variable "deployment_generation" {'
deployment_block=$(sed -n '/variable "deployment_generation" {/,/^}/p' "$variables")
grep -Eq '^[[:space:]]*nullable[[:space:]]*=[[:space:]]*false$' <<<"$deployment_block" || fail "deployment_generation must be required and non-null"
if grep -Eq '^[[:space:]]*default[[:space:]]*=' <<<"$deployment_block"; then
  fail "deployment_generation must not have a reusable default"
fi

if rg -n 'smsv2_site_generation|variable "site_prefix"' "$aws_root" --glob '*.tf'; then
  fail "AWS root retains a legacy or bypassable generation input"
fi
require_text "$locals_file" 'site_prefix         = "${var.component}-${var.deployment_generation}"'
require_text "$locals_file" 'deployment_generation = var.deployment_generation'
require_text "$locals_file" '"mcn-deployment-generation" = var.deployment_generation'

if rg -n '\$\{var\.component\}-aws' "$aws_root" --glob '*.tf'; then
  fail "an AWS/XC resource name or Name tag bypasses the immutable deployment generation"
fi
require_text "$tgw" 'name_prefix                = local.aws_resource_prefix'
require_text "$tgw" 'name        = "${local.aws_resource_prefix}-aws-tgw-${replace(each.key, "_", "-")}"'

for resource in xcsh_token xcsh_securemesh_site_v2 xcsh_virtual_site xcsh_origin_pool xcsh_http_loadbalancer; do
  block=$(sed -n "/resource \"$resource\" /,/^}/p" "$xc")
  grep -Fq 'labels' <<<"$block" || fail "$resource must carry deployment-generation labels"
done
for resource in xcsh_external_connector xcsh_bgp; do
  block=$(sed -n "/resource \"$resource\" /,/^}/p" "$tgw")
  grep -Fq 'labels' <<<"$block" || fail "$resource must carry deployment-generation labels"
done

printf 'PASS: every AWS and XC identity is bound to one required immutable deployment generation\n'
