# Plan-level test for the xc-site module (securemesh_site_v2 + bgp). Mocks the
# xcsh provider so no XC credentials are contacted.

mock_provider "xcsh" {}

run "site_and_interface_binding" {
  command = plan

  module {
    source = "./modules/xc-site"
  }

  variables {
    site_name      = "mcn-ce-ha-eastus01"
    hostname       = "f5-xc-ce-vm-01"
    interface_name = "ves-io-securemesh-site-v2-mcn-ce-ha-eastus01-network-f5-xc-ce-vm-01-eth0-0"
    rs_peer_ips    = ["10.0.4.4", "10.0.4.5"]
    ce_asn         = 64512
    rs_asn         = 65515
    admin_password = "MockSitePassword-42!"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
    # enable_bgp remains at its true default.
  }

  assert {
    condition     = output.site_name == "mcn-ce-ha-eastus01"
    error_message = "Site name should be mcn-ce-ha-eastus01."
  }

  assert {
    condition     = output.interface_name == "ves-io-securemesh-site-v2-mcn-ce-ha-eastus01-network-f5-xc-ce-vm-01-eth0-0"
    error_message = "Interface name should be the XC auto-derived object name the BGP peer binds to."
  }

  assert {
    condition     = xcsh_securemesh_site_v2.this.namespace == "system"
    error_message = "The site must be created in the system namespace."
  }

  assert {
    condition = (
      xcsh_securemesh_site_v2.this.admin_user_credentials.ssh_key == var.ssh_public_key &&
      xcsh_securemesh_site_v2.this.admin_user_credentials.admin_password.clear_secret_info.url == "string:///TW9ja1NpdGVQYXNzd29yZC00MiE="
    )
    error_message = "The site must configure its node-local admin credential through the supported Base64 secret URL."
  }

  # Provider v3.80.0 gave perf_mode_l7_enhanced a {jumbo_disabled | jumbo_enabled}
  # sub-oneof. F5 materialises jumbo_disabled server-side while a create stores null
  # for it, so leaving both members undeclared makes the site re-plan the marker as a
  # change on every plan after the create — it never reaches 0 changes.
  #
  # These two assertions pin WHICH member is declared; they cannot catch the member
  # being dropped entirely, because the mocked provider resolves jumbo_disabled to {}
  # and jumbo_enabled to null in the plan whether or not the config declares either.
  # That was verified by running this file against the module with and without the
  # declaration — both pass. The discriminating check is a live plan, recorded on the
  # pull request; what is guarded here is a silent switch to the jumbo_enabled arm,
  # which would change the data path.
  assert {
    condition = (
      xcsh_securemesh_site_v2.this.performance_enhancement_mode.perf_mode_l7_enhanced.jumbo_disabled != null
    )
    error_message = "perf_mode_l7_enhanced must declare the jumbo_disabled arm."
  }

  assert {
    condition = (
      xcsh_securemesh_site_v2.this.performance_enhancement_mode.perf_mode_l7_enhanced.jumbo_enabled == null
    )
    error_message = "perf_mode_l7_enhanced must NOT select jumbo_enabled: jumbo_disabled is the arm F5 materialises, and switching arms changes the CE data path."
  }
}
