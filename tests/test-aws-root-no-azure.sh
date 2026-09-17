#!/usr/bin/env bash
# The AWS lifecycle root must remain usable after Azure access has been removed.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform/aws" && pwd)
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
data_dir=$(mktemp -d)
trap "rm -rf \"$data_dir\"" EXIT

for forbidden in azurerm azapi azuread libvirt docker; do
  if rg -q "${forbidden}" "$root" --glob "*.tf"; then
    printf "FAIL: AWS root references forbidden provider %s\\n" "$forbidden" >&2
    exit 1
  fi
done

# The AWS root pins the released provider. Refresh an ignored local lock rather
# than allowing a previous workstation install to make this isolation test
# report a stale-provider failure.
TF_DATA_DIR="$data_dir" terraform -chdir="$root" init -backend=false -upgrade -input=false >/dev/null

printf "PASS: AWS root has no Azure, KVM, or Docker provider dependency\\n"
