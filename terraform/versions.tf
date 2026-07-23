terraform {
  # >= 1.8 for provider-defined functions and the check{} block used to guard the
  # HA VIP against the VNet CIDRs (see main.tf).
  required_version = ">= 1.8"

  required_providers {
    xcsh = {
      source = "f5-sales-demo/xcsh"
      # >= 3.72.15 matches the org baseline used by the sibling webapp-api-protection
      # plan. The CE-HA data-plane resources (securemesh_site_v2 explicit-interface,
      # bgp per-peer named-interface ref, http_loadbalancer advertise_custom) are all
      # present in this line. Consumed locally via ~/.terraformrc dev_overrides.
      version = ">= 3.72.15"
    }
    # Azure providers deploy the hub VNet, Azure Route Server, the CE VMs and the
    # test client. azuread is read-only (resolves the deployer identity for naming/tags).
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}
