resource "aws_eip" "recovery" {
  #checkov:skip=CKV2_AWS_19: Import-only recovery must not mutate an orphan EIP attachment before the reviewed destroy plan.
  for_each = local.collisions_by_type.aws_eip
  domain   = "vpc"
  tags     = each.value.observed_tags

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_ec2_transit_gateway_connect_peer" "recovery" {
  for_each                      = local.collisions_by_type.aws_ec2_transit_gateway_connect_peer
  inside_cidr_blocks            = each.value.observed_config.inside_cidr_blocks
  peer_address                  = each.value.observed_config.peer_address
  transit_gateway_attachment_id = each.value.observed_config.transit_gateway_attachment_id
  bgp_asn                       = try(each.value.observed_config.bgp_asn, null)
  transit_gateway_address       = try(each.value.observed_config.transit_gateway_address, null)
  tags                          = each.value.observed_tags

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_instance" "recovery" {
  #checkov:skip=CKV_AWS_135: Import-only recovery must preserve the observed instance configuration until its reviewed destroy plan.
  #checkov:skip=CKV_AWS_126: Import-only recovery must not enable monitoring on a legacy instance before retirement.
  #checkov:skip=CKV_AWS_79: Import-only recovery must not alter observed instance metadata settings before retirement.
  #checkov:skip=CKV_AWS_8: Import-only recovery must not alter observed EBS settings before retirement.
  for_each = local.collisions_by_type.aws_instance

  ami                    = each.value.observed_config.ami
  instance_type          = each.value.observed_config.instance_type
  subnet_id              = each.value.observed_config.subnet_id
  vpc_security_group_ids = each.value.observed_config.vpc_security_group_ids
  iam_instance_profile   = try(each.value.observed_config.iam_instance_profile, null)
  key_name               = try(each.value.observed_config.key_name, null)
  tags                   = each.value.observed_tags

  # Terraform reverses this creation edge during the reviewed destroy plan:
  # instances terminate before their attached EIPs are released.
  depends_on = [aws_eip.recovery]

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_key_pair" "recovery" {
  for_each   = local.collisions_by_type.aws_key_pair
  key_name   = each.value.name
  public_key = var.recovery_public_key
  tags       = each.value.observed_tags

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_iam_role" "recovery" {
  for_each = local.collisions_by_type.aws_iam_role
  name     = each.value.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = each.value.observed_tags

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_iam_instance_profile" "recovery" {
  for_each = local.collisions_by_type.aws_iam_instance_profile
  name     = each.value.name
  role     = one(values(aws_iam_role.recovery)).name
  tags     = each.value.observed_tags

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_lb" "recovery" {
  #checkov:skip=CKV_AWS_131: The adopted object is a TCP Network Load Balancer; HTTP header handling is an ALB control.
  #checkov:skip=CKV_AWS_150: Enabling deletion protection would mutate the orphan and prevent the authorized recovery destroy.
  #checkov:skip=CKV_AWS_91: Enabling access logging would violate the required import-only zero-update recovery plan.
  #checkov:skip=CKV2_AWS_28: The adopted object is a Network Load Balancer; AWS WAF association applies to ALBs.
  for_each                         = local.collisions_by_type.aws_lb
  name                             = each.value.name
  internal                         = data.aws_lb.recovery[each.key].internal
  load_balancer_type               = data.aws_lb.recovery[each.key].load_balancer_type
  subnets                          = data.aws_lb.recovery[each.key].subnets
  enable_cross_zone_load_balancing = data.aws_lb.recovery[each.key].enable_cross_zone_load_balancing
  tags                             = each.value.observed_tags

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_lb_target_group" "recovery" {
  for_each    = local.collisions_by_type.aws_lb_target_group
  name        = each.value.name
  port        = data.aws_lb_target_group.recovery[each.key].port
  protocol    = data.aws_lb_target_group.recovery[each.key].protocol
  target_type = data.aws_lb_target_group.recovery[each.key].target_type
  vpc_id      = data.aws_lb_target_group.recovery[each.key].vpc_id
  tags        = each.value.observed_tags

  lifecycle {
    ignore_changes = all
  }
}

# An import-only recovery configuration must still satisfy the AWS provider
# schema.  Read the required immutable shape from the verified, manifest-bound
# object rather than inventing replacement values.  These data reads add no
# mutation edge and lifecycle.ignore_changes above prevents an adoption plan
# from proposing drift repair.
data "aws_lb" "recovery" {
  for_each = local.collisions_by_type.aws_lb
  arn      = each.value.resource_uid
}

data "aws_lb_target_group" "recovery" {
  for_each = local.collisions_by_type.aws_lb_target_group
  arn      = each.value.resource_uid
}

resource "xcsh_token" "recovery" {
  for_each  = local.collisions_by_type.xcsh_token
  name      = each.value.name
  namespace = each.value.namespace
  labels    = each.value.observed_labels
  depends_on = [
    xcsh_securemesh_site_v2.recovery,
  ]

  lifecycle {
    ignore_changes = all
  }
}

resource "xcsh_securemesh_site_v2" "recovery" {
  for_each  = local.collisions_by_type.xcsh_securemesh_site_v2
  name      = each.value.name
  namespace = each.value.namespace
  labels = {
    for key, value in each.value.observed_labels : key => value
    if !contains(local.discovered_site_labels, key)
  }

  lifecycle {
    ignore_changes = all
  }
}

resource "xcsh_virtual_site" "recovery" {
  for_each  = local.collisions_by_type.xcsh_virtual_site
  name      = each.value.name
  namespace = each.value.namespace
  labels    = each.value.observed_labels
  depends_on = [
    xcsh_securemesh_site_v2.recovery,
  ]

  lifecycle {
    ignore_changes = all
  }
}

resource "xcsh_origin_pool" "recovery" {
  for_each  = local.collisions_by_type.xcsh_origin_pool
  name      = each.value.name
  namespace = each.value.namespace
  labels    = each.value.observed_labels

  lifecycle {
    ignore_changes = all
  }
}

resource "xcsh_http_loadbalancer" "recovery" {
  for_each  = local.collisions_by_type.xcsh_http_loadbalancer
  name      = each.value.name
  namespace = each.value.namespace
  domains   = [var.recovery_placeholder_domain]
  labels    = each.value.observed_labels
  depends_on = [
    xcsh_origin_pool.recovery,
  ]

  lifecycle {
    ignore_changes = all
  }
}

# BGP is intentionally dependent on its connector so a reviewed destroy plan
# removes the BGP object first, before retiring the connector it references.
resource "xcsh_external_connector" "recovery" {
  for_each  = local.collisions_by_type.xcsh_external_connector
  name      = each.value.name
  namespace = each.value.namespace
  labels    = each.value.observed_labels
  depends_on = [
    xcsh_securemesh_site_v2.recovery,
  ]

  lifecycle {
    ignore_changes = all
  }
}

resource "xcsh_bgp" "recovery" {
  for_each  = local.collisions_by_type.xcsh_bgp
  name      = each.value.name
  namespace = each.value.namespace
  labels    = each.value.observed_labels
  depends_on = [
    xcsh_external_connector.recovery,
  ]

  lifecycle {
    ignore_changes = all
  }
}
