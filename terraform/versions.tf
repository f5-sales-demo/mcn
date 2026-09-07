terraform {
  # >= 1.16.1 for provider-defined actions and saved-plan invocation.
  required_version = ">= 1.16.1"

  required_providers {
    xcsh = {
      source  = "f5-sales-demo/xcsh"
      version = "= 8.0.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
      version = "~> 0.8.0"
    }
  }
}
