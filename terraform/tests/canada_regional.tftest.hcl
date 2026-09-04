# Test suite for Canada Regional infrastructure, Virtual Sites, and HTTP Load Balancer.

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}
mock_provider "aws" {}
mock_provider "libvirt" {}

variables {
  site_prefix            = null
  ca_site_prefix         = null
  lb_name                = null
  ca_lb_name             = null
  origin_pool_name       = null
  ca_origin_pool_name    = null
  route_server_name      = null
  ca_route_server_name   = null
  bastion_name           = null
  ca_bastion_name        = null
  client_vm_name         = null
  ca_client_vm_name      = null
  region_short           = null
  ca_region_short        = null
  resource_group_name    = null
  ca_resource_group_name = null
  lb_domain              = "mcn-ce-ha.f5-sales-demo.com"
  ca_lb_domain           = "mcn-ce-ha.f5-sales-demo.ca"
  origin_ip              = "203.0.113.10"
  deployer               = "tester"
  ssh_public_key         = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  xc_app_namespace       = "multi-cloud-networking"
  enable_aws             = false
  enable_canada          = true
}

run "canada_regional_virtual_sites_and_lb" {
  command = plan

  variables {
    ce_count    = 2
    ca_ce_count = 3
  }

  assert {
    condition     = output.ca_re_virtual_site_name == "mcn-ce-ha-ca-re-vsite"
    error_message = "Canada RE Virtual Site name should be mcn-ce-ha-ca-re-vsite."
  }

  assert {
    condition     = output.ca_ce_virtual_site_name == "mcn-ce-ha-ca-ce-vsite"
    error_message = "Canada CE Virtual Site name should be mcn-ce-ha-ca-ce-vsite."
  }

  assert {
    condition     = output.ca_lb_domain == "mcn-ce-ha.f5-sales-demo.ca"
    error_message = "Canada HTTP Load Balancer domain should be mcn-ce-ha.f5-sales-demo.ca."
  }

  assert {
    condition     = output.ca_loadbalancer_name == "mcn-ce-ha-ca-f5se"
    error_message = "Canada HTTP Load Balancer name should be mcn-ce-ha-ca-f5se."
  }

  assert {
    condition     = output.ca_origin_pool_name == "mcn-ce-ha-ca-pool"
    error_message = "Canada Origin Pool name should be mcn-ce-ha-ca-pool."
  }

  assert {
    condition     = output.ca_vip == "10.250.1.10"
    error_message = "Canada VIP should be 10.250.1.10."
  }
}

run "canada_disabled_plans_no_canada_resources" {
  command = plan

  variables {
    enable_canada = false
  }

  assert {
    condition     = length(xcsh_virtual_site.canada_re) == 0
    error_message = "With enable_canada = false, no Canada RE virtual site should be created."
  }

  assert {
    condition     = length(xcsh_http_loadbalancer.canada) == 0
    error_message = "With enable_canada = false, no Canada HTTP load balancer should be created."
  }

  assert {
    condition     = output.ca_re_virtual_site_name == null
    error_message = "With enable_canada = false, ca_re_virtual_site_name output must be null."
  }
}
