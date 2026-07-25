terraform {
  # >= 1.8 for provider-defined functions and the check{} block used to guard the
  # HA VIP against the VNet CIDRs (see main.tf).
  required_version = ">= 1.8"

  required_providers {
    xcsh = {
      source = "f5-sales-demo/xcsh"
      # The floor carries every provider capability this deployment depends on:
      # the xcsh_token resource's Computed `uid` attribute (the CE registration
      # token VALUE), the object-ref name validator relaxed 63 -> 128 chars (so
      # the real 71-char auto-derived SLO interface name that the BGP peer binds
      # to validates), and the registration pair used by modules/xc-site — the
      # xcsh_site_registration data source (resolves a CE's r-<uuid> runtime
      # registration name from its site name) plus xcsh_registration_approval.
      version = ">= 3.78.0" # TODO(controller): confirm released version
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
