locals {
  # --- F5 XC tenant endpoint ---
  # Every F5 XC tenant is served at https://<tenant>.console.ves.volterra.io, so
  # naming the tenant is enough to name the API. providers.tf feeds this to the
  # xcsh provider's api_url, which is what makes the TENANT A PROPERTY OF THE
  # CONFIGURATION rather than of whatever XCSH_API_URL the shell happens to hold.
  xc_api_url = "https://${var.expected_xc_tenant}.console.ves.volterra.io"

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

  # --- CE site registration token fed to cloud-init ---
  # Prefer the provider-generated xcsh_token.ce.uid (the Computed token VALUE);
  # an explicit var.registration_token still wins when supplied (break-glass /
  # externally-minted token). Empty var (default) => the generated token.
  ce_registration_token = var.registration_token != "" ? var.registration_token : xcsh_token.ce.uid

  # --- CE cloud-init, rendered once per node ---
  # Rendered here rather than inline in the module block so the document is
  # addressable as local.ce_cloud_init in `terraform test` — the rendered YAML is
  # the whole contract with the appliance, and it is only worth asserting if it can
  # be read. See tests/cloud_init.tftest.hcl.
  ce_cloud_init = {
    for key, node in module.ce_topology.ce_nodes : key => templatefile("${path.module}/cloud-init/ce-node.yaml", {
      cluster_name = node.site_name
      token        = local.ce_registration_token
      # chomp: a key read from a .pub file ends in a newline, which would render a
      # second, empty line into authorized_keys under `content: |`.
      ssh_public_key = chomp(local.ssh_public_key)
    })
  }
}
