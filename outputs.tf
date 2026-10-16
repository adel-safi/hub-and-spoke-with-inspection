output "hub_vpc_id" {
  value = aws_vpc.hub.id
}

output "spoke_vpc_ids" {
  value = { for k, s in module.spoke : k => s.vpc_id }
}

output "transit_gateway_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "firewall_arn" {
  value = aws_networkfirewall_firewall.this.arn
}

output "firewall_endpoints" {
  description = "Network Firewall VPC endpoint per AZ."
  value       = local.firewall_endpoints
}

output "nat_public_ips" {
  description = "Public IPs all spoke egress traffic is NATed to."
  value       = { for az, e in aws_eip.nat : az => e.public_ip }
}

output "firewall_log_groups" {
  value = {
    alert = aws_cloudwatch_log_group.firewall_alert.name
    flow  = aws_cloudwatch_log_group.firewall_flow.name
  }
}

output "test_instances" {
  description = "Test instance IDs and private IPs, with the command to open a shell on each."
  value = {
    for k, i in aws_instance.test : k => {
      id         = i.id
      private_ip = i.private_ip
      connect    = "aws ssm start-session --region ${var.region} --target ${i.id}"
    }
  }
}
