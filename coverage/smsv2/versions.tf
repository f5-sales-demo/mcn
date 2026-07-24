terraform {
  required_providers {
    xcsh = {
      source = "f5-sales-demo/xcsh"
    }
  }
}

# Local runs use ~/.terraformrc dev_overrides → ../../terraform-provider-xcsh build.
# Do NOT run `terraform init` (dev_overrides forbids it); use plan/apply directly.
provider "xcsh" {}
