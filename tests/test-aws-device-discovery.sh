#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
aws_xc="$repo_root/terraform/aws/aws_xc.tf"
aws_ce="$repo_root/terraform/aws/aws_ce.tf"
aws_upgrade="$repo_root/terraform/aws/aws_upgrade.tf"
variables="$repo_root/terraform/aws/variables_aws.tf"

fail() {
  printf "FAIL: %s\\n" "$*" >&2
  exit 1
}
require() { grep -Fq "$1" "$2" || fail "missing $1 in $2"; }
reject() { ! grep -Fq "$1" "$2" || fail "unexpected $1 in $2"; }

require "variable \"aws_site_configuration_phase\"" "$variables"
require "\"discovery\", \"configured\"" "$variables"
reject "variable \"aws_smsv2_devices\"" "$variables"

require "data \"xcsh_site_registrations_by_site\" \"aws\"" "$aws_xc"
require "aws_discovered_device_candidates" "$aws_xc"
require "aws_discovered_devices" "$aws_xc"
require "mac_address" "$aws_xc"
require "aws_network_interface.slo" "$aws_xc"
require "aws_network_interface.sli" "$aws_xc"
require "var.aws_site_configuration_phase == \"configured\"" "$aws_xc"
require "not_managed {" "$aws_xc"
reject "var.aws_smsv2_devices" "$aws_xc"
require "Discovery creates and registers CEs only" "$variables"

# A configured plan must use the registration's device name only after the
# exact Terraform-owned ENI MAC has one matching hardware record. These source
# assertions protect the zero-mutation failure boundary for absent/ambiguous
# observations without needing cloud credentials in CI.
require "length(local.aws_discovered_device_candidates[each.key].slo) == 1" "$aws_xc"
require "length(local.aws_discovered_device_candidates[each.key].sli) == 1" "$aws_xc"
require "local.aws_discovered_devices[each.key].slo != local.aws_discovered_devices[each.key].sli" "$aws_xc"
require "requires exactly one nonempty registered hardware device" "$aws_xc"
require "do not guess guest device names" "$aws_xc"

# The discovery phase is intentionally a site/CE-only graph. It cannot create
# Connect peers before an observed MAC-to-device binding exists.
require "var.aws_site_configuration_phase == \"configured\" || !var.enable_aws_tgw_connect" "$variables"
require "set aws_site_configuration_phase to configured before enabling AWS TGW Connect" "$variables"

require "ignore_changes = [user_data]" "$aws_ce"

# Discovery is intentionally pre-registration. Upgrade status is meaningful
# only in the configured phase after the runtime gate can succeed.
require 'var.aws_site_configuration_phase == "configured" && contains(var.aws_upgrade_observed_sites, key)' "$aws_upgrade"
reject 'for key, site in local.aws_sites : key => site if contains(var.aws_upgrade_observed_sites, key)' "$aws_upgrade"

printf "PASS: AWS SMSv2 device discovery is staged, exact-MAC-bound, fail-closed, and replacement-safe\\n"
