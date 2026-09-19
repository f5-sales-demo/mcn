output "aws_vpc_id" {
  description = "AWS VPC ID."
  value       = try(aws_vpc.aws[0].id, null)
}

output "aws_workload_vpc_id" {
  description = "Dedicated AWS workload VPC identity."
  value       = try(aws_vpc.workload[0].id, null)
}

output "aws_workload_instance_id" {
  description = "Amazon Linux SSM client identity."
  value       = try(aws_instance.workload[0].id, null)
}

output "aws_workload_private_ip" {
  description = "Private address of the Amazon Linux SSM client."
  value       = try(aws_instance.workload[0].private_ip, null)
}

output "aws_origin_dns_name" {
  description = "DNS name of the external HTTP origin used by the AWS SMSv2 showcase."
  value       = var.aws_origin_dns_name
}

output "aws_site_names" {
  description = "Canonical independent AWS SecureMesh v2 site names."
  value       = { for key, site in local.aws_sites : key => site.name }
}

output "aws_smsv2_owned_eni_projection" {
  description = "Private Terraform-owned AWS ENI MAC projection for the one-to-one bootstrap registration join."
  sensitive   = true
  value = flatten([
    for key, site in local.aws_sites : [
      { site_key = key, role = "slo", mac = aws_network_interface.slo[site.index].mac_address },
      { site_key = key, role = "sli", mac = aws_network_interface.sli[site.index].mac_address },
    ]
  ])
}

output "aws_smsv2_bootstrap_registration_projection" {
  description = "Private observed bootstrap hardware projection. Device values are joined to the owned ENI MAC projection outside Git."
  sensitive   = true
  value = flatten([
    for key, registration in data.xcsh_site_registrations_by_site.aws_bootstrap : [
      for item in coalesce(try(registration.items, null), []) : [
        for network in try(item.get_spec.infra.hw_info.network, []) : {
          site_key = key
          mac      = network.mac_address
          device   = network.name
        }
      ]
    ]
  ])
}

output "aws_tgw_id" {
  description = "AWS Transit Gateway identity."
  value       = try(module.aws_tgw_connect[0].transit_gateway_id, null)
}

output "aws_tgw_route_table_id" {
  description = "TGW route table used for explicit workload association and propagation."
  value       = try(module.aws_tgw_connect[0].route_table_id, null)
}

output "aws_ce_instance_ids" {
  description = "EC2 instance IDs of the AWS Customer Edge nodes."
  value       = aws_instance.ce[*].id
}

output "aws_ce_public_ips" {
  description = "Elastic IPs assigned to the AWS Customer Edge nodes."
  value       = aws_eip.ce[*].public_ip
}

output "aws_lb_domain" {
  description = "Domain served by the AWS HTTP load balancer."
  value       = var.aws_lb_domain
}

output "aws_loadbalancer_name" {
  description = "Name of the AWS HTTP load balancer."
  value       = try(xcsh_http_loadbalancer.aws[0].name, null)
}

output "aws_origin_pool_name" {
  description = "Name of the AWS origin pool."
  value       = try(xcsh_origin_pool.aws[0].name, null)
}

output "aws_vip" {
  description = "Plan-bound private IP of the internal NLB fronting the three BGP-routed SMSv2 listeners."
  value       = var.aws_vip
}

output "aws_smsv2_site_listener_ips" {
  description = "Per-site automatic SLI listener addresses exported over TGW Connect BGP."
  value       = { for key, site in local.aws_sites : key => site.listener_ip }
}

output "aws_smsv2_nlb_dns_name" {
  description = "Internal AWS NLB DNS name for the SMSv2 service."
  value       = try(aws_lb.smsv2[0].dns_name, null)
}

output "aws_smsv2_target_group_arn" {
  description = "Target group containing the three BGP-routed SMSv2 site listeners."
  value       = try(aws_lb_target_group.smsv2[0].arn, null)
}
