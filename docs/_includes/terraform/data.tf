# Deployer identity resolution (read-only, azuread). Only evaluated during a
# real root plan/apply — the plan-level tests target child modules and/or mock
# the azuread provider, so these are never read without credentials.
data "azuread_client_config" "current" {}

data "azuread_user" "current" {
  count     = var.deployer == "" ? 1 : 0
  object_id = data.azuread_client_config.current.object_id
}
