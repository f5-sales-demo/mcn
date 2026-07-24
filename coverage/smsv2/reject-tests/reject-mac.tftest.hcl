# DESIGNED TO FAIL — proves ethernet_interface.mac validator MACValidator() rejects a malformed MAC.
# One reject run per file: a failing run halts the rest of its own file, so each leaf gets
# its own file to guarantee its validator fires. Run via verify.sh (not plain terraform test).
# mock_provider => no credentials; validator fires from the real v3.75.1 schema at plan.
# string_arms defaults true, so the mac leaf is wired on the eth0 ethernet_interface.
mock_provider "xcsh" {}

run "reject_mac_malformed" {
  command = plan

  variables {
    probe_name = "cov-probe-s2-mac"
    mac        = "not-a-mac"
  }
}
