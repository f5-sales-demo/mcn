# DESIGNED TO FAIL — proves static_ip.default_gw validator IPValidator() rejects a non-IP value.
# Run via verify.sh (not plain terraform test). mock_provider => no credentials.
# string_arms defaults true, so the static_ip block (ip_address + default_gw) is rendered.
mock_provider "xcsh" {}

run "reject_default_gw_not_an_ip" {
  command = plan

  variables {
    probe_name = "cov-probe-s2-gw"
    default_gw = "10.0.0.256"
  }
}
