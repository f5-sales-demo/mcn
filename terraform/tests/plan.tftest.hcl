# Root integration plan test. Mocks all three providers so the whole graph
# (hub -> CE VMs -> XC sites/bgp -> RS bgp connections -> client -> origin pool +
# HTTP LB) plans with no Azure or XC credentials. Passing ssh_public_key material
# means the root never reads a key file.

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}

run "root_plans_end_to_end" {
  command = plan

  variables {
    ce_count = 2
    deployer = "tester"
    # enable_bgp is left at its true default so the root integration test plans the WHOLE
    # graph, bgp objects included. It used to be forced false only to dodge the provider's
    # object-ref name length cap, relaxed in v3.74.0 (see modules/xc-site/main.tf).
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  }

  assert {
    condition     = output.loadbalancer_name == "ar-bgp-ecmp-lb"
    error_message = "Load balancer name should be ar-bgp-ecmp-lb."
  }

  assert {
    condition     = output.origin_pool_name == "wsp-demo-pool"
    error_message = "Origin pool name should be wsp-demo-pool."
  }

  assert {
    condition     = output.ce_count == 2
    error_message = "ce_count=2 should deploy two CE nodes."
  }

  assert {
    condition     = output.xc_site_names["eastus01"] == "ar-bgp-eastus01"
    error_message = "CE-01 XC site name should be ar-bgp-eastus01."
  }

  assert {
    condition     = output.vip == "10.250.0.10"
    error_message = "VIP should be 10.250.0.10."
  }
}
