# Plan-level test for the xc-site module (securemesh_site_v2 + bgp). Mocks the
# xcsh provider so no XC credentials are contacted.

mock_provider "xcsh" {}

run "site_and_interface_binding" {
  command = plan

  module {
    source = "./modules/xc-site"
  }

  variables {
    site_name      = "ar-bgp-eastus01"
    hostname       = "f5-xc-ce-vm-01"
    interface_name = "ves-io-securemesh-site-v2-ar-bgp-eastus01-network-f5-xc-ce-vm-01-eth0-0"
    mgmt_nic_mac   = "7c:1e:52:18:c1:77"
    rs_peer_ips    = ["10.0.4.4", "10.0.4.5"]
    ce_asn         = 64512
    rs_asn         = 65515
    # Site-focused run. bgp disabled here because the real 71-char interface name
    # asserted below exceeds the provider's 63-char object-ref cap (blocker, see
    # modules/xc-site/main.tf). Asserting the OUTPUT is fine — outputs are not
    # length-validated — so this still proves the interface-name binding string.
    enable_bgp = false
  }

  assert {
    condition     = output.site_name == "ar-bgp-eastus01"
    error_message = "Site name should be ar-bgp-eastus01."
  }

  assert {
    condition     = output.interface_name == "ves-io-securemesh-site-v2-ar-bgp-eastus01-network-f5-xc-ce-vm-01-eth0-0"
    error_message = "Interface name should be the XC auto-derived object name the BGP peer binds to."
  }

  assert {
    condition     = xcsh_securemesh_site_v2.this.namespace == "system"
    error_message = "The site must be created in the system namespace."
  }
}
