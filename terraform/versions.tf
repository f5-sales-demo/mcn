terraform {
  # >= 1.8 for provider-defined functions and the check{} block used to guard the
  # HA VIP against the VNet CIDRs (see main.tf).
  required_version = ">= 1.8"

  required_providers {
    xcsh = {
      source = "f5-sales-demo/xcsh"
      # >= 3.74.0 carries the xcsh_token resource's Computed `uid` attribute (the
      # CE registration token VALUE) and the object-ref name validator relaxed
      # 63 -> 128 chars (so the real 71-char auto-derived SLO interface name that
      # the BGP peer binds to now validates). Consumed locally via ~/.terraformrc
      # dev_overrides; the registry pin turns green once v3.74.0 publishes.
      version = ">= 3.74.0"
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
