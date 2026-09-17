import {
  for_each = local.collisions_by_type.aws_eip
  to       = aws_eip.recovery[each.key]
  id       = each.value.resource_uid
}

import {
  for_each = local.collisions_by_type.aws_ec2_transit_gateway_connect_peer
  to       = aws_ec2_transit_gateway_connect_peer.recovery[each.key]
  id       = each.value.resource_uid
}


import {
  for_each = local.collisions_by_type.aws_instance
  to       = aws_instance.recovery[each.key]
  id       = each.value.resource_uid
}
import {
  for_each = local.collisions_by_type.aws_key_pair
  to       = aws_key_pair.recovery[each.key]
  id       = each.value.name
}

import {
  for_each = local.collisions_by_type.aws_iam_role
  to       = aws_iam_role.recovery[each.key]
  id       = each.value.name
}

import {
  for_each = local.collisions_by_type.aws_iam_instance_profile
  to       = aws_iam_instance_profile.recovery[each.key]
  id       = each.value.name
}

import {
  for_each = local.collisions_by_type.aws_lb
  to       = aws_lb.recovery[each.key]
  id       = each.value.resource_uid
}

import {
  for_each = local.collisions_by_type.aws_lb_target_group
  to       = aws_lb_target_group.recovery[each.key]
  id       = each.value.resource_uid
}

import {
  for_each = local.collisions_by_type.xcsh_token
  to       = xcsh_token.recovery[each.key]
  id       = "${each.value.namespace}/${each.value.name}"
}

import {
  for_each = local.collisions_by_type.xcsh_securemesh_site_v2
  to       = xcsh_securemesh_site_v2.recovery[each.key]
  id       = "${each.value.namespace}/${each.value.name}"
}

import {
  for_each = local.collisions_by_type.xcsh_virtual_site
  to       = xcsh_virtual_site.recovery[each.key]
  id       = "${each.value.namespace}/${each.value.name}"
}

import {
  for_each = local.collisions_by_type.xcsh_origin_pool
  to       = xcsh_origin_pool.recovery[each.key]
  id       = "${each.value.namespace}/${each.value.name}"
}

import {
  for_each = local.collisions_by_type.xcsh_http_loadbalancer
  to       = xcsh_http_loadbalancer.recovery[each.key]
  id       = "${each.value.namespace}/${each.value.name}"
}

import {
  for_each = local.collisions_by_type.xcsh_external_connector
  to       = xcsh_external_connector.recovery[each.key]
  id       = "${each.value.namespace}/${each.value.name}"
}

import {
  for_each = local.collisions_by_type.xcsh_bgp
  to       = xcsh_bgp.recovery[each.key]
  id       = "${each.value.namespace}/${each.value.name}"
}
