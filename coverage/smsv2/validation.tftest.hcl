# S1 numeric- + S2 string-leaf input validation for xcsh_securemesh_site_v2 (provider >= 3.75.1).
#
# POSITIVE case: valid bounds AND valid mac/ip/CIDR/node-type plan cleanly through the REAL
# provider schema. mock_provider means no XC credentials are needed — the schema (and its
# numeric + string validators) come from the dev_overrides build locally / the registry v3.75.1
# in CI, and fire during plan regardless of whether the API is contacted.
#
# The out-of-range REJECT cases live in ./reject-tests/reject.tftest.hcl. They cannot be
# asserted with `expect_failures` because Terraform only captures user-defined custom
# conditions there, not provider schema attribute validators (verified: TF 1.15 reports
# "was expected to report an error but did not"). They are instead proven by verify.sh,
# which runs them expecting failure and asserts the exact validator message for each leaf.

mock_provider "xcsh" {}

run "accept_valid_bounds" {
  command = plan

  variables {
    probe_name      = "cov-probe-s1-ok"
    mtu             = 1500                # AtMost(16384)
    priority        = 0                   # Between(0, 255)   lower bound
    vlan_id         = 4095                # Between(1, 4095)  upper bound
    proxy_port      = 0                   # Between(0, 65535) lower bound
    mac             = "7C-1E-52-7F-F8-12" # MACValidator()
    node_type       = "Worker"            # OneOf("Control", "Worker") — the non-default valid arm
    ip_address      = "10.0.1.5/24"       # CIDRValidator()
    default_gw      = "10.0.1.1"          # IPValidator()
    vrf_string_arms = true                # render sli_config so the IPv4Validator leaves are reached
    nameserver      = "10.0.2.53"         # IPv4Validator()
    vip             = "10.0.2.100"        # IPv4Validator()
  }

  assert {
    condition     = xcsh_securemesh_site_v2.probe.namespace == "system"
    error_message = "Probe must plan in the system namespace."
  }

  assert {
    condition     = length(xcsh_securemesh_site_v2.probe.azure.not_managed.node_list[0].interface_list) == 2
    error_message = "extended_arms must render both the eth0 and eth0-vlan interfaces so every numeric leaf is reachable."
  }

  assert {
    condition     = xcsh_securemesh_site_v2.probe.azure.not_managed.node_list[0].type == "Worker"
    error_message = "A valid node type (Worker) must pass the OneOf(Control, Worker) validator and plan clean."
  }

  assert {
    condition     = xcsh_securemesh_site_v2.probe.azure.not_managed.node_list[0].interface_list[0].static_ip.ip_address == "10.0.1.5/24"
    error_message = "string_arms must render the static_ip block so a valid CIDR ip_address plans clean."
  }

  assert {
    condition     = xcsh_securemesh_site_v2.probe.local_vrf.sli_config.vip == "10.0.2.100"
    error_message = "vrf_string_arms must render sli_config so a valid IPv4 nameserver/vip plans clean through IPv4Validator."
  }
}
