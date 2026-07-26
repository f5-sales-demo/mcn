# DESIGNED TO FAIL — proves static_ipv6_address.node_static_ip.ip_address validator CIDRValidator()
# rejects a malformed IPv6 CIDR. Run via verify.sh (not plain terraform test). mock_provider => no
# credentials; validator fires from the real provider schema at plan. ipv6_arm=static_ipv6_address
# renders node_static_ip so the ip_address leaf is reachable. The malformed value differs from the
# S2 static_ip reject ("999.999.0.0/8") so its exact diagnostic is unambiguous.
mock_provider "xcsh" {}

run "reject_static_ipv6_bad_cidr" {
  command = plan

  variables {
    probe_name   = "cov-probe-s3-ipv6-bad"
    ipv6_arm     = "static_ipv6_address"
    ipv6_address = "2001:db8::gg/64"
  }
}
