terraform {
  # >= 1.10.0 for provider-defined functions, check{} blocks, and test framework
  # mocking options (override_during = plan in .tftest.hcl).
  required_version = ">= 1.10.0"

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
      # >= 3.77.5 additionally carries the two fixes that retire the labels
      # workaround in modules/xc-site: import-marker suppression for the nested
      # interface_list `labels {}` block (#1244) and preservation of a
      # config-declared empty top-level metadata `labels` map (#1286).
      # >= 3.81.1 is where xcsh_registration_approval first WORKS. Below it every
      # approve omitted the required `passport` and the API returned 500
      # "Validation approval: Passport is required" (xcsh#1355), so
      # approve_registration = true — the default, and the whole point of the
      # hands-off two-phase deploy — could never complete; approvals had to be
      # POSTed out of band and imported. The provider now derives `passport`
      # server-side (reads the sibling registration and echoes it verbatim), so
      # it is not a Terraform attribute and modules/xc-site needs no change.
      version = ">= 3.81.1"
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
    # Runs scripts/xc-env-tenant.sh at plan time so the tenant guard in main.tf can
    # see XCSH_API_URL. Terraform cannot read the environment itself, and the guard
    # has to work with no credentials of any kind, which rules out asking the API.
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    # Generates one Site Console admin password per CE. No version constraint:
    # this deployment deliberately resolves the latest provider on every init.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
