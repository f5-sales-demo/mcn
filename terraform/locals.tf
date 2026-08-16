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

  # --- Derived object names ---
  # Every name in the deployment descends from var.component (plus the resolved
  # deployer for the resource group, which is per-person by nature). Terraform
  # variable defaults cannot reference other variables, so each of these variables
  # defaults to null and is resolved here instead; an explicit value always wins.
  #
  # The point is that NO object name is a literal anyone has to maintain, and none
  # can carry a customer's or an individual's name by accident: change
  # var.component and the sites, load balancer, origin pool, Route Server, Bastion
  # and resource group all follow.
  region_short        = coalesce(var.region_short, var.location)
  site_prefix         = coalesce(var.site_prefix, var.component)
  resource_group_name = coalesce(var.resource_group_name, "rg-${var.component}-${local.deployer}")
  route_server_name   = coalesce(var.route_server_name, "${var.component}-rs")
  bastion_name        = coalesce(var.bastion_name, "${var.component}-bastion")
  client_vm_name      = coalesce(var.client_vm_name, "${var.component}-client")
  origin_pool_name    = coalesce(var.origin_pool_name, "${var.component}-pool")
  # `-f5se` matches the convention this tenant's other load balancers already use.
  lb_name = coalesce(var.lb_name, "${var.component}-f5se")

  # --- Derived Canada object names ---
  ca_region_short        = coalesce(var.ca_region_short, var.ca_location)
  ca_site_prefix         = coalesce(var.ca_site_prefix, "${var.component}-ca")
  ca_resource_group_name = coalesce(var.ca_resource_group_name, "rg-${var.component}-ca-${local.deployer}")
  ca_route_server_name   = coalesce(var.ca_route_server_name, "${var.component}-ca-rs")
  ca_bastion_name        = coalesce(var.ca_bastion_name, "${var.component}-ca-bastion")
  ca_client_vm_name      = coalesce(var.ca_client_vm_name, "${var.component}-ca-client")
  ca_origin_pool_name    = coalesce(var.ca_origin_pool_name, "${var.component}-ca-pool")
  ca_lb_name             = coalesce(var.ca_lb_name, "${var.component}-ca-f5se")
  ca_re_vsite_name       = coalesce(var.ca_re_vsite_name, "${var.component}-ca-re-vsite")
  ca_ce_vsite_name       = coalesce(var.ca_ce_vsite_name, "${var.component}-ca-ce-vsite")

  aws_site_prefix = coalesce(var.aws_site_prefix, "${var.component}-aws")

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
