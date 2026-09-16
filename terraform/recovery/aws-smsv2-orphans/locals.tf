locals {
  manifest   = jsondecode(file(var.ownership_manifest_path))
  collisions = try(local.manifest.collisions, [])
  supported_types = toset([
    "aws_iam_instance_profile",
    "aws_iam_role",
    "aws_key_pair",
    "aws_lb",
    "aws_lb_target_group",
    "xcsh_http_loadbalancer",
    "xcsh_origin_pool",
    "xcsh_securemesh_site_v2",
    "xcsh_token",
    "xcsh_virtual_site",
  ])
  collisions_by_type = {
    for resource_type in local.supported_types : resource_type => {
      for collision in local.collisions : collision.address => collision
      if collision.type == resource_type
    }
  }
}

check "manifest_identity" {
  assert {
    condition = (
      try(local.manifest.schema_version, 0) == 2 &&
      try(local.manifest.status, "") == "blocked" &&
      try(local.manifest.recovery_mode, "") == "legacy_unlabelled" &&
      try(local.manifest.plan_sha256, "") == var.source_plan_sha256 &&
      try(local.manifest.aws_account_id, "") == var.aws_account_id &&
      try(local.manifest.aws_region, "") == var.aws_region &&
      try(local.manifest.xc_tenant, "") == var.xc_tenant &&
      try(local.manifest.creator_id, "") == var.creator_id &&
      try(local.manifest.component, "") == var.component &&
      try(local.manifest.deployment_generation, "") == var.deployment_generation
    )
    error_message = "The recovery manifest identity does not match the explicitly expected plan, cloud, tenant, owner, component and generation."
  }
}

check "manifest_collision_evidence" {
  assert {
    condition = (
      length(local.collisions) > 0 &&
      length(distinct([for collision in local.collisions : collision.address])) == length(local.collisions) &&
      length(distinct([for collision in local.collisions : collision.resource_uid])) == length(local.collisions) &&
      alltrue([for collision in local.collisions : contains(local.supported_types, collision.type)]) &&
      alltrue([for collision in local.collisions :
        (collision.engine == "aws" && startswith(collision.type, "aws_")) ||
        (collision.engine == "f5" && startswith(collision.type, "xcsh_"))
      ]) &&
      alltrue([for collision in local.collisions : collision.ownership == "verified"]) &&
      alltrue([for collision in local.collisions : collision.generation_binding == "saved_plan_name_and_legacy_ownership"]) &&
      alltrue([for collision in local.collisions : startswith(collision.name, "${var.component}-${var.deployment_generation}-")]) &&
      alltrue([for collision in local.collisions : length(collision.resource_uid) > 0]) &&
      try(can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T", local.manifest.inventory_captured_at)), false) &&
      alltrue([for collision in local.collisions : try(length(collision.created_at) > 0, false) || length(collision.creation_evidence) > 0]) &&
      alltrue([for collision in local.collisions : collision.engine == "aws" || (
        collision.engine == "f5" && collision.creator_id == var.creator_id &&
        collision.xc_tenant == var.xc_tenant && length(collision.namespace) > 0
      )]) &&
      alltrue([for collision in local.collisions : collision.engine == "f5" || (
        collision.engine == "aws" && collision.aws_account_id == var.aws_account_id &&
        collision.aws_region == var.aws_region &&
        try(collision.observed_tags.component, "") == var.component
      )])
    )
    error_message = "The recovery manifest contains unsupported, duplicate, unowned or insufficiently evidenced collisions."
  }
}
