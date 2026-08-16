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
# It stays 3.80.0 rather than tracking the deployment release because this isolated probe verifies
# the minimum provider contract that first exposed every Secure Mesh v2 arm it exercises.
#
# This floor is the ONLY TRACKED place a provider version is pinned (`.terraform.lock.hcl` also
# pins one at runtime, but it is gitignored, so it cannot be a source of truth for a reader). Do
# not restate a version in a comment in main.tf / verify.sh / *.tftest.hcl: those copies drifted
# across four releases before S8 removed them.
#
# ALWAYS run against a REGISTRY release, never a local build:
#
#   printf 'provider_installation {\n  direct {}\n}\n' > /tmp/tfrc
#   TF_CLI_CONFIG_FILE=/tmp/tfrc terraform init -upgrade   # confirm the log names the version
#
# A `dev_overrides` entry in ~/.terraformrc silently masks the registry release with a local
# working-tree build. That build lags the released schema, and the failure is not obviously a
# version problem — a pre-v3.80.0 build rejects this probe with
# `Blocks of type "jumbo_disabled" are not expected here`, which reads like a config error.
# dev_overrides also forbids `terraform init`, so the lock file cannot be refreshed while it is
# active. TF_CLI_CONFIG_FILE overrides ~/.terraformrc entirely, which is why it is the only
# supported way to drive this probe.
provider "xcsh" {}
