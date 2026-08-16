# Node-local access is configured through the Secure Mesh v2 site contract.
# The API receives each password through its deterministic clear-secret URL
# contract; no cloud VM extension mutates the CE operating system after boot.

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}
mock_provider "aws" {}
mock_provider "libvirt" {}
mock_provider "docker" {}
mock_provider "random" {
  mock_resource "random_password" {
    defaults = { result = "MockSitePassword-42!" }
  }
}

variables {
  subscription_id = uuidv5("dns", "example.com")
  lb_domain       = "mcn.example.com"
  origin_ip       = "198.51.100.10"
  deployer        = "tester"
  ce_count        = 1
  enable_bastion  = false
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
}

run "site_credentials_use_the_f5xc_contract" {
  command = plan

  assert {
    condition = (
      length(random_password.site_console_admin) == 1 &&
      length(random_password.site_console_admin_ca) == 3 &&
      length(random_password.site_console_admin_aws) == 3 &&
      length(random_password.site_console_admin_kvm) == 1
    )
    error_message = "Every default Secure Mesh v2 site must receive one independently generated admin password."
  }

  assert {
    condition = alltrue([
      for site in values(module.xc_site) : site.site_name != ""
    ])
    error_message = "Every Azure site module must be configured through the Secure Mesh v2 site resource."
  }

  assert {
    condition = alltrue([
      for site in values(xcsh_securemesh_site_v2.aws) :
      site.admin_user_credentials.ssh_key == var.ssh_public_key &&
      startswith(site.admin_user_credentials.admin_password.clear_secret_info.url, "string:///")
    ])
    error_message = "Every AWS site must configure the supported admin credential with a Base64 clear-secret URL."
  }

  assert {
    condition = (
      xcsh_securemesh_site_v2.kvm[0].admin_user_credentials.ssh_key == var.ssh_public_key &&
      startswith(xcsh_securemesh_site_v2.kvm[0].admin_user_credentials.admin_password.clear_secret_info.url, "string:///")
    )
    error_message = "The KVM site must configure the supported admin credential with a Base64 clear-secret URL."
  }
}

run "site_credentials_follow_opt_outs" {
  command = plan

  variables {
    enable_canada = false
    enable_aws    = false
    enable_kvm    = false
  }

  assert {
    condition = (
      length(random_password.site_console_admin_ca) == 0 &&
      length(random_password.site_console_admin_aws) == 0 &&
      length(random_password.site_console_admin_kvm) == 0
    )
    error_message = "Admin credentials must be gated by the same opt-out switches as their sites."
  }
}
