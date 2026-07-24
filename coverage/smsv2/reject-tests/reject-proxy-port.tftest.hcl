# DESIGNED TO FAIL — proves custom_proxy.proxy_port validator Between(0, 65535) rejects >65535.
# Run via verify.sh (not plain terraform test). mock_provider => no credentials.
mock_provider "xcsh" {}

run "reject_proxy_port_over_max" {
  command = plan

  variables {
    probe_name = "cov-probe-s1-proxy"
    mtu        = 1500
    priority   = 10
    vlan_id    = 100
    proxy_port = 70000
  }
}
