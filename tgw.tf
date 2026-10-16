# Transit Gateway with two route tables:
#
#   spokes     - associated with every spoke attachment.
#                0.0.0.0/0 -> hub attachment, so ALL spoke traffic (east-west and egress)
#                is forced through the inspection VPC.
#   inspection - associated with the hub attachment.
#                Spoke CIDRs are propagated here so inspected traffic can return to its spoke.

resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name} hub-and-spoke"
  amazon_side_asn                 = 64512
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"

  tags = { Name = "${var.name}-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.hub.id
  subnet_ids         = [for az in local.azs : aws_subnet.hub_tgw[az].id]

  # Keeps both directions of a flow on the same AZ / firewall endpoint, which
  # stateful inspection requires.
  appliance_mode_support = "enable"

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "${var.name}-hub" }
}

resource "aws_ec2_transit_gateway_route_table" "spokes" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = { Name = "${var.name}-spokes" }
}

resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = { Name = "${var.name}-inspection" }
}

# Hub attachment -> inspection route table
resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# Spokes send everything to the hub
resource "aws_ec2_transit_gateway_route" "spokes_default_to_hub" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

# Spoke attachments -> spokes route table, and propagate into inspection route table
resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = module.spoke

  transit_gateway_attachment_id  = each.value.tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke" {
  for_each = module.spoke

  transit_gateway_attachment_id  = each.value.tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}
