# DESIGNED TO FAIL — proves vlan_interface.vlan_id validator Between(1, 4095) rejects >4095.
# Run via verify.sh (not plain terraform test). mock_provider => no credentials.
mock_provider "xcsh" {}

run "reject_vlan_id_over_max" {
  command = plan

  variables {
    probe_name = "cov-probe-s1-vlan"
    mtu        = 1500
    priority   = 10
    vlan_id    = 4096
    proxy_port = 8080
  }
}
