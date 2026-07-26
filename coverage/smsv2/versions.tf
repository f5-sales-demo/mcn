terraform {
  required_version = ">= 1.8"
  required_providers {
    xcsh = {
      source  = "f5-sales-demo/xcsh"
      version = ">= 3.80.0"
    }
  }
}

# 3.80.0 is the floor because it is the first release carrying the `x-f5xc-wire-name` contract
# (specs v2.1.194): `blocked_services` cannot round-trip on anything older (provider #1257).
#
# Local runs use ~/.terraformrc dev_overrides → ../../terraform-provider-xcsh build,
# which overrides the version constraint above (a warning is expected, not an error).
# Do NOT run `terraform init` (dev_overrides forbids it); use plan/apply directly. To run against the
# pinned registry release instead, set TF_CLI_CONFIG_FILE to an empty file and `init` (see README).
provider "xcsh" {}
