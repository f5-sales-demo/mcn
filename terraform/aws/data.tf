data "external" "xc_env_tenant" {
  program = ["${path.module}/scripts/xc-env-tenant.sh"]

  lifecycle {
    postcondition {
      condition     = contains(["", var.expected_xc_tenant], self.result.tenant)
      error_message = "Wrong F5 XC tenant for this AWS-only state key."
    }
  }
}

data "xcsh_namespace" "mcn" {
  name      = var.xc_app_namespace
  namespace = ""
}
