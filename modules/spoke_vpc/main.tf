# Spoke VPC: private workload subnets plus small dedicated TGW attachment subnets.
# No IGW or NAT - every non-local packet goes to the Transit Gateway and on to the hub for inspection.

locals {
  az_index = { for i, az in var.azs : az => i }
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

resource "aws_subnet" "workload" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, each.value) # x.y.0.0/24, x.y.1.0/24, ...

  tags = { Name = "${var.name}-workload-${each.key}" }
}

resource "aws_subnet" "tgw" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 12, 4080 + each.value) # x.y.255.0/28, x.y.255.16/28, ...

  tags = { Name = "${var.name}-tgw-${each.key}" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.this.id
  subnet_ids         = [for az in var.azs : aws_subnet.tgw[az].id]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = var.name }
}

resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-workload" }
}

resource "aws_route" "default_to_tgw" {
  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route_table_association" "workload" {
  for_each = aws_subnet.workload

  subnet_id      = each.value.id
  route_table_id = aws_route_table.workload.id
}
