#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root="$repo_root/terraform"
lifecycle="$repo_root/scripts/showcase-lifecycle.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require() {
  grep -Fq -- "$1" "$2" || fail "missing $1 in ${2#"$repo_root"/}"
}

reject() {
  ! grep -Fq -- "$1" "$2" || fail "unexpected $1 in ${2#"$repo_root"/}"
}

test ! -d "$root/aws" || fail 'terraform/aws remains as a second active root'

require 'required_version = "= 1.16.3"' "$root/versions.tf"
require 'variable "aws_site_configuration_phase"' "$root/variables_aws.tf"
require 'variable "aws_smsv2_device_mapping_file"' "$root/variables_aws.tf"
require 'data "xcsh_site_registrations_by_site" "kvm"' "$root/onprem_kvm.tf"
require 'resource "xcsh_registration_approval" "kvm"' "$root/onprem_kvm.tf"
require 'data "xcsh_site_bgp_status" "kvm"' "$root/onprem_kvm.tf"
test -f "$root/tests/kvm_registration_mapping.tftest.hcl" || fail 'KVM registration mapping fixtures are missing'
require 'configured_kvm_mapping_is_exact' "$root/tests/kvm_registration_mapping.tftest.hcl"
require 'configured_kvm_mapping_rejects_missing_owned_mac' "$root/tests/kvm_registration_mapping.tftest.hcl"
require 'configured_kvm_mapping_rejects_duplicate_owned_mac' "$root/tests/kvm_registration_mapping.tftest.hcl"
require 'configured_kvm_mapping_rejects_foreign_provider' "$root/tests/kvm_registration_mapping.tftest.hcl"
require 'kvm {' "$root/onprem_kvm.tf"
reject 'azure {' "$root/onprem_kvm.tf"

test -x "$lifecycle" || fail 'scripts/showcase-lifecycle.sh is missing or not executable'
require 'bootstrap' "$lifecycle"
require 'bootstrap_retirement' "$lifecycle"
require 'configured' "$lifecycle"
require 'getent passwd "$(id -un)"' "$lifecycle"
require '/PASSWORDS.txt' "$lifecycle"
require '(8#$credential_mode & 077) == 0' "$lifecycle"
require 'terraform-with-aws-sso.sh' "$lifecycle"
require 'preflight_kvm_image()' "$lifecycle"
require "-target='data.xcsh_site_image.kvm'" "$lifecycle"
require 'maurice_config_cardinality_exactly_one' "$lifecycle"
require 'systemctl enable --now' "$lifecycle"
require 'terraform plan' "$lifecycle"
require 'tf apply -input=false -no-color "$PLAN_FILE"' "$lifecycle"
require 'plan -destroy' "$lifecycle"
require "-var='enable_kvm=false'" "$lifecycle"
require 'plan -refresh-only' "$lifecycle"
require 'refresh-only plan did not isolate the expected drift' "$lifecycle"
require 'virsh --connect qemu:///system autostart --disable' "$lifecycle"
require 'managed KVM domain autostart drift was not repaired' "$lifecycle"
require 'exercise_managed_drift first' "$lifecycle"
require 'exercise_managed_drift second' "$lifecycle"
reject 'terraform destroy' "$lifecycle"
reject 'terraform import' "$lifecycle"
reject 'terraform state rm' "$lifecycle"

image_preflight_line=$(grep -n '^[[:space:]]*preflight_kvm_image$' "$lifecycle" | tail -1 | cut -d: -f1)
service_mutation_line=$(grep -n 'sudo -n systemctl enable --now' "$lifecycle" | head -1 | cut -d: -f1)
test -n "$image_preflight_line" || fail 'KVM image preflight call is missing'
test -n "$service_mutation_line" || fail 'libvirt service mutation is missing'
test "$image_preflight_line" -lt "$service_mutation_line" ||
  fail 'KVM image issuance must be proven before libvirt or Docker service mutation'

printf 'PASS: unified AWS and KVM lifecycle contract is enforced\n'
