terraform {
  required_version = ">= 1.16.2"

  # The bootstrap starts locally because it creates this bucket, then migrates
  # itself to its dedicated key after the reviewed apply succeeds.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "replica"
  region = var.replica_region
}
