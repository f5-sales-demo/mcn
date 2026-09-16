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

printf 'PASS: every AWS IAM instance profile in the Azure-free root carries ownership tags\n'
