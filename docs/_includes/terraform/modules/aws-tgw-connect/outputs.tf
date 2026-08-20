output "transit_gateway_id" {
  description = "Transit Gateway ID."
  value       = aws_ec2_transit_gateway.this.id
}

output "connect_attachment_id" {
  description = "Transit Gateway Connect attachment ID."
  value       = aws_ec2_transit_gateway_connect.this.id
}

output "connect_peer_ids" {
  description = "Connect peer IDs keyed by telemetry-attested CE interface."
  value       = { for key, peer in aws_ec2_transit_gateway_connect_peer.this : key => peer.id }
}

output "route_ids" {
  description = "Transit Gateway route IDs keyed by destination CIDR."
  value       = { for cidr, route in aws_ec2_transit_gateway_route.this : cidr => route.id }
}
