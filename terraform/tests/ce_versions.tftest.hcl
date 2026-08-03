# Plan-level test asserting that ce_os_version and ce_sw_version reject empty strings.
# Empty is not neutral: at create time F5 XC fills an empty field with the newest advertised
# version, making installed versions depend on the date of apply (#726).

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}

variables {
  site_prefix         = null
  lb_name             = null
  origin_pool_name    = null
  route_server_name   = null
  bastion_name        = null
  client_vm_name      = null
  region_short        = null
  resource_group_name = null
  deployer            = "tester"
  lb_domain           = "mcn-ce-ha.f5-sales-demo.com"
  origin_ip           = "203.0.113.10"
  ssh_public_key      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  ce_os_version       = "9.2024.6"
  ce_sw_version       = "crt-20250613-3382"
}

run "empty_ce_os_version_is_rejected" {
  command = plan

  variables {
    ce_os_version = ""
  }

  expect_failures = [var.ce_os_version]
}

run "empty_ce_sw_version_is_rejected" {
  command = plan

  variables {
    ce_sw_version = ""
  }

  expect_failures = [var.ce_sw_version]
}
