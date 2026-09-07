# Deployer identity resolution (read-only, azuread). An explicit deployer makes
# the lookup unnecessary, which keeps AWS-only planning from contacting Azure.
data "azuread_client_config" "current" {
  count = var.deployer == "" ? 1 : 0
}

data "azuread_user" "current" {
  count     = var.deployer == "" ? 1 : 0
  object_id = data.azuread_client_config.current[0].object_id
}
