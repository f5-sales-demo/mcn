locals {
  xc_api_url          = "https://${var.expected_xc_tenant}.console.ves.volterra.io"
  site_prefix         = "${var.component}-${var.deployment_generation}"
  aws_resource_prefix = local.site_prefix
  deployer            = replace(lower(var.deployer), "/[^a-z0-9]/", "")
  tags = merge({
    component             = var.component
    environment           = var.environment
    deployer              = local.deployer
    managed_by            = "terraform"
    deployment_generation = var.deployment_generation
  }, var.tags)
  xc_labels = {
    "mcn-deployment-generation" = var.deployment_generation
    "mcn-topology"              = "${local.site_prefix}-aws"
  }
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand(var.ssh_public_key_path))
}
