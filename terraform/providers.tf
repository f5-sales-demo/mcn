# The xcsh provider takes its CREDENTIAL from the environment — no secrets in
# code — but NOT its endpoint. Export one of the following before running
# Terraform:
#
#   Token auth:  XCSH_API_TOKEN
#   P12 auth:    XCSH_P12_FILE + XCSH_P12_PASSWORD
#   PEM auth:    XCSH_CERT + XCSH_KEY
#
# api_url is derived from var.expected_xc_tenant and overrides an ambient
# XCSH_API_URL. A credential minted for another tenant fails against this explicit
# URL. Plan tests mock the provider and require no XC credential.
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

# AWS — deploys the VPC, subnets, CE EC2 instances and internet gateway.
# Auth comes from the environment (aws CLI login / AWS_* env vars).
provider "aws" {
  region = var.aws_location
}

# Read-only: resolves the deployer identity for resource naming/tags.
provider "azuread" {}
