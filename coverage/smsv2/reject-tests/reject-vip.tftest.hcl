# DESIGNED TO FAIL — proves local_vrf.sli_config.vip validator IPv4Validator() rejects a
# non-IPv4 value (an IPv6 literal, proving the validator is IPv4-specific). Run via verify.sh
# (not plain terraform test). mock_provider => no credentials. vrf_string_arms=true renders sli_config.
mock_provider "xcsh" {}

run "reject_vip_not_ipv4" {
  command = plan

  variables {
    probe_name      = "cov-probe-s2-vip"
    vrf_string_arms = true
    vip             = "2001:db8::1"
  }
}
