provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

provider "xcsh" {
  api_url = "https://${var.xc_tenant}.console.ves.volterra.io"
}
