provider "aws" {
  region = var.aws_location
}

provider "xcsh" {
  api_url = local.xc_api_url
}
