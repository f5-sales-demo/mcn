terraform {
  required_version = ">= 1.16.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    xcsh = {
      source  = "f5-sales-demo/xcsh"
      version = "= 9.2.6"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}
