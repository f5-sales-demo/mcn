# S1 numeric-leaf input validation for xcsh_securemesh_site_v2 (provider >= 3.75.0).
#
# POSITIVE case: valid bounds plan cleanly through the REAL provider schema.
# mock_provider means no XC credentials are needed — the schema (and its numeric
# validators) come from the dev_overrides build locally / the registry v3.75.0 in CI,
# and fire during plan regardless of whether the API is contacted.
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
    probe_name = "cov-probe-s1-ok"
    mtu        = 1500 # AtMost(16384)
    priority   = 0    # Between(0, 255)   lower bound
    vlan_id    = 4095 # Between(1, 4095)  upper bound
    proxy_port = 0    # Between(0, 65535) lower bound
  }

  assert {
    condition     = xcsh_securemesh_site_v2.probe.namespace == "system"
    error_message = "Probe must plan in the system namespace."
  }

  assert {
    condition     = length(xcsh_securemesh_site_v2.probe.azure.not_managed.node_list[0].interface_list) == 2
    error_message = "extended_arms must render both the eth0 and eth0-vlan interfaces so every numeric leaf is reachable."
  }
}
