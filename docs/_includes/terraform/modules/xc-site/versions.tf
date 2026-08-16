terraform {
  required_version = ">= 1.8"

  required_providers {
    xcsh = {
      source = "f5-sales-demo/xcsh"
      # Keep in lock-step with the root terraform/versions.tf.
      version = ">= 3.77.5"
    }
  }
}
