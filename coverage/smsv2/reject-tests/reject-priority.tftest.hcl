# DESIGNED TO FAIL — proves interface_list.priority validator Between(0, 255) rejects >255.
# Run via verify.sh (not plain terraform test). mock_provider => no credentials.
mock_provider "xcsh" {}

run "reject_priority_over_max" {
  command = plan

  variables {
    probe_name = "cov-probe-s1-prio"
    mtu        = 1500
    priority   = 256
    vlan_id    = 100
    proxy_port = 8080
  }
}
