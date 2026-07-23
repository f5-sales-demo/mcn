locals {
  # --- Deployer resolution (4-tier fallback) ---
  # 1. Explicit override via var.deployer
  # 2a. Azure AD: given_name initial + surname
  # 2b. Azure AD: mail prefix (guest/external accounts)
  # 3. Object ID hash (service principals, managed identities)
  deployer_from_name = (
    var.deployer == "" && length(data.azuread_user.current) > 0
    ? try(
      lower("${substr(data.azuread_user.current[0].given_name, 0, 1)}${data.azuread_user.current[0].surname}"),
      ""
    )
    : ""
  )

  deployer_from_mail = (
    var.deployer == "" && length(data.azuread_user.current) > 0 && local.deployer_from_name == ""
    ? try(
      lower(split("@", data.azuread_user.current[0].mail)[0]),
      ""
    )
    : ""
  )

  deployer_from_oid = substr(sha1(data.azuread_client_config.current.object_id), 0, 8)

  deployer_resolved = coalesce(
    var.deployer,
    local.deployer_from_name,
    local.deployer_from_mail,
    local.deployer_from_oid
  )

  deployer = replace(lower(local.deployer_resolved), "/[^a-z0-9]/", "")

  # --- Standard tags (applied to every Azure resource) ---
  standard_tags = {
    component   = var.component
    environment = var.environment
    deployer    = local.deployer
    managed_by  = "terraform"
  }

  tags = merge(local.standard_tags, var.tags)

  # --- SSH public key material, read once at the root ---
  # When ssh_public_key material is supplied (e.g. by the plan tests) it wins and
  # no file is read; otherwise read the key file once and pass the string down.
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand(var.ssh_public_key_path))
}
