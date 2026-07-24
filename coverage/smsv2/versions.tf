terraform {
  required_version = ">= 1.8"
  required_providers {
    xcsh = {
      source  = "f5-sales-demo/xcsh"
      version = ">= 3.74.0"
    }
  }
}

# Local runs use ~/.terraformrc dev_overrides → ../../terraform-provider-xcsh build,
# which overrides the version constraint above (a warning is expected, not an error).
# Do NOT run `terraform init` (dev_overrides forbids it); use plan/apply directly.
provider "xcsh" {}
