# DESIGNED TO FAIL — proves static_ip.ip_address validator CIDRValidator() rejects a bad CIDR.
# Run via verify.sh (not plain terraform test). mock_provider => no credentials.
# string_arms defaults true, so the static_ip block (ip_address + default_gw) is rendered.
mock_provider "xcsh" {}

run "reject_ip_address_bad_cidr" {
  command = plan

  variables {
    probe_name = "cov-probe-s2-ip"
    ip_address = "999.999.0.0/8"
  }
}
