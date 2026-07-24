# DESIGNED TO FAIL — proves local_vrf.sli_config.nameserver validator IPv4Validator() rejects a
# malformed IPv4. Run via verify.sh (not plain terraform test). mock_provider => no credentials.
# vrf_string_arms=true renders the sli_config block so the nameserver leaf is reachable at plan.
mock_provider "xcsh" {}

run "reject_nameserver_bad_ipv4" {
  command = plan

  variables {
    probe_name      = "cov-probe-s2-ns"
    vrf_string_arms = true
    nameserver      = "300.1.1.1"
  }
}
