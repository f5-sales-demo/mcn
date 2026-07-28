# The xcsh provider takes its CREDENTIAL from the environment — no secrets in
# code — but NOT its endpoint. Export one of the following before running
# Terraform:
#
#   Token auth:  XCSH_API_TOKEN
#   P12 auth:    XCSH_P12_FILE + XCSH_P12_PASSWORD
#   PEM auth:    XCSH_CERT + XCSH_KEY
#
# api_url is set here, from var.expected_xc_tenant, and deliberately overrides any
# XCSH_API_URL in the environment. The tenant is not an ambient property of the
# operator's shell: it is which deployment this is, it belongs in version control
# next to the state key, and it is the one thing a credential file must not be
# able to change silently. It once did — see the guard in main.tf and issue #696.
#
# A credential minted for a different tenant now fails against this URL instead of
# succeeding somewhere unintended. The plan-level tests mock this provider, so no
# XC credentials are needed to run `terraform test`.
provider "xcsh" {
  api_url = local.xc_api_url
}

# Azure — deploys the hub VNet, Route Server, CE VMs and the test client.
# Auth comes from the environment (az CLI login locally; ARM_* / a service
# principal in CI). Only the subscription is set here, from a variable.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Read-only: resolves the deployer identity for resource naming/tags.
provider "azuread" {}
