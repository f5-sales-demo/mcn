terraform {
  # >= 1.10.0 for provider-defined functions, check{} blocks, and test framework
  # mocking options (override_during = plan in .tftest.hcl).
  required_version = ">= 1.10.0"

  required_providers {
    xcsh = {
      source  = "f5-sales-demo/xcsh"
      version = ">= 3.81.1"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.60"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.8"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.5"
    }
  }
}
