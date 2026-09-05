# Provider-defined actions remain asynchronous. Operators invoke software and
# then OS for one site at a time; the read-only status data source supplies the
# bounded convergence gate.
action "xcsh_site_upgrade_sw" "aws" {
  for_each = local.aws_sites

  config {
    name      = each.value.name
    namespace = "system"
    version   = var.aws_target_software_version
    force     = false
  }
}

action "xcsh_site_upgrade_os" "aws" {
  for_each = local.aws_sites

  config {
    name      = each.value.name
    namespace = "system"
    version   = var.aws_target_os_version
    force     = false
  }
}

data "xcsh_site_upgrade_status" "aws" {
  for_each = { for key, site in local.aws_sites : key => site if contains(var.aws_upgrade_observed_sites, key) }

  namespace                 = "system"
  site                      = xcsh_securemesh_site_v2.aws[each.key].name
  expected_software_version = var.aws_target_software_version
  expected_os_version       = var.aws_target_os_version
  wait                      = var.aws_upgrade_wait
  timeout_seconds           = var.aws_upgrade_timeout_seconds
  poll_interval_seconds     = var.aws_upgrade_poll_interval_seconds

  depends_on = [xcsh_registration_approval.aws]
}

output "aws_site_upgrade_status" {
  description = "Sanitized per-site software, OS, readiness, eligibility, and convergence observations."
  value = {
    for key, status in data.xcsh_site_upgrade_status.aws : key => {
      site                         = local.aws_sites[key].name
      software_installed_version   = status.software_installed_version
      software_available_version   = status.software_available_version
      software_deployment_phase    = status.software_deployment_phase
      software_deployment_result   = status.software_deployment_result
      os_installed_version         = status.os_installed_version
      os_available_version         = status.os_available_version
      os_deployment_phase          = status.os_deployment_phase
      os_deployment_result         = status.os_deployment_result
      site_state                   = status.site_state
      upgradable_software_versions = status.upgradable_software_versions
      failed_precheck_names        = status.failed_precheck_names
      eligible                     = status.eligible
      ready                        = status.ready
      target_converged             = status.target_converged
    }
  }
}

output "aws_upgrade_convergence" {
  description = "Aggregate target and baseline identities for the serial three-site upgrade run."
  value = var.enable_aws ? {
    baseline_software = var.aws_baseline_software_version
    baseline_os       = var.aws_baseline_os_version
    target_software   = var.aws_target_software_version
    target_os         = var.aws_target_os_version
    all_ready         = alltrue([for status in values(data.xcsh_site_upgrade_status.aws) : status.ready])
    all_converged     = alltrue([for status in values(data.xcsh_site_upgrade_status.aws) : status.target_converged])
  } : null
}
