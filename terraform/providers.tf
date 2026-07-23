# The xcsh provider authenticates from the environment — no secrets in code.
# Export one of the following credential sets before running Terraform:
#
#   Token auth:  XCSH_API_URL + XCSH_API_TOKEN
#   P12 auth:    XCSH_API_URL + XCSH_P12_FILE + XCSH_P12_PASSWORD
#   PEM auth:    XCSH_API_URL + XCSH_CERT + XCSH_KEY
#
# See terraform/README notes / CONTRIBUTING.md for local dev setup
# (dev_overrides + env). The plan-level tests mock this provider, so no XC
# credentials are needed to run `terraform test`.
provider "xcsh" {}

# Azure — deploys the hub VNet, Route Server, CE VMs and the test client.
# Auth comes from the environment (az CLI login locally; ARM_* / a service
# principal in CI). Only the subscription is set here, from a variable.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Read-only: resolves the deployer identity for resource naming/tags.
provider "azuread" {}
