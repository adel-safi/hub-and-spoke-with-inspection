# Hub (inspection) VPC
#
# Per AZ:
#   tgw subnet (/28)      - TGW attachment ENIs.        0.0.0.0/0      -> firewall endpoint (same AZ)
#   firewall subnet (/28) - Network Firewall endpoint.  0.0.0.0/0      -> NAT gateway (same AZ)
#                                                       internal range -> TGW
#   public subnet (/24)   - NAT gateway.                0.0.0.0/0      -> IGW
#                                                       spoke CIDRs    -> firewall endpoint (same AZ, return path)

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs         = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  az_index    = { for i, az in local.azs : az => i }
  spoke_cidrs = [for s in values(var.spokes) : s.cidr]

  # Return path from the NAT gateways to each spoke, per AZ.
  public_return_routes = {
    for pair in setproduct(local.azs, local.spoke_cidrs) :
    "${pair[0]}|${pair[1]}" => { az = pair[0], cidr = pair[1] }
  }

  # AZ -> Network Firewall VPC endpoint ID.
  firewall_endpoints = {
    for s in aws_networkfirewall_firewall.this.firewall_status[0].sync_states :
    s.availability_zone => s.attachment[0].endpoint_id
  }
}

resource "aws_vpc" "hub" {
  cidr_block           = var.hub_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-hub" }
}

resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id

  tags = { Name = "${var.name}-hub-igw" }
}

# --- Subnets ---------------------------------------------------------------

resource "aws_subnet" "hub_tgw" {
  for_each = local.az_index

  vpc_id            = aws_vpc.hub.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.hub_cidr, 12, each.value) # 10.0.0.0/28, 10.0.0.16/28, ...

  tags = { Name = "${var.name}-hub-tgw-${each.key}" }
}

resource "aws_subnet" "hub_firewall" {
  for_each = local.az_index

  vpc_id            = aws_vpc.hub.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.hub_cidr, 12, 16 + each.value) # 10.0.1.0/28, 10.0.1.16/28, ...

  tags = { Name = "${var.name}-hub-firewall-${each.key}" }
}

resource "aws_subnet" "hub_public" {
  for_each = local.az_index

  vpc_id            = aws_vpc.hub.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.hub_cidr, 8, 10 + each.value) # 10.0.10.0/24, 10.0.11.0/24, ...

  tags = { Name = "${var.name}-hub-public-${each.key}" }
}

# --- NAT gateways (centralized egress) ------------------------------------

resource "aws_eip" "nat" {
  for_each = local.az_index

  domain = "vpc"

  tags = { Name = "${var.name}-hub-nat-${each.key}" }
}

resource "aws_nat_gateway" "hub" {
  for_each = local.az_index

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.hub_public[each.key].id

  tags = { Name = "${var.name}-hub-nat-${each.key}" }

  depends_on = [aws_internet_gateway.hub]
}

# --- Route tables: TGW subnets --------------------------------------------

resource "aws_route_table" "hub_tgw" {
  for_each = local.az_index

  vpc_id = aws_vpc.hub.id

  tags = { Name = "${var.name}-hub-tgw-${each.key}" }
}

resource "aws_route" "hub_tgw_to_firewall" {
  for_each = local.az_index

  route_table_id         = aws_route_table.hub_tgw[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoints[each.key]
}

resource "aws_route_table_association" "hub_tgw" {
  for_each = local.az_index

  subnet_id      = aws_subnet.hub_tgw[each.key].id
  route_table_id = aws_route_table.hub_tgw[each.key].id
}

# --- Route tables: firewall subnets ---------------------------------------

resource "aws_route_table" "hub_firewall" {
  for_each = local.az_index

  vpc_id = aws_vpc.hub.id

  tags = { Name = "${var.name}-hub-firewall-${each.key}" }
}

resource "aws_route" "hub_firewall_to_nat" {
  for_each = local.az_index

  route_table_id         = aws_route_table.hub_firewall[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.hub[each.key].id
}

resource "aws_route" "hub_firewall_to_tgw" {
  for_each = local.az_index

  route_table_id         = aws_route_table.hub_firewall[each.key].id
  destination_cidr_block = var.internal_supernet
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route_table_association" "hub_firewall" {
  for_each = local.az_index

  subnet_id      = aws_subnet.hub_firewall[each.key].id
  route_table_id = aws_route_table.hub_firewall[each.key].id
}

# --- Route tables: public subnets -----------------------------------------

resource "aws_route_table" "hub_public" {
  for_each = local.az_index

  vpc_id = aws_vpc.hub.id

  tags = { Name = "${var.name}-hub-public-${each.key}" }
}

resource "aws_route" "hub_public_to_igw" {
  for_each = local.az_index

  route_table_id         = aws_route_table.hub_public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.hub.id
}

resource "aws_route" "hub_public_to_firewall" {
  for_each = local.public_return_routes

  route_table_id         = aws_route_table.hub_public[each.value.az].id
  destination_cidr_block = each.value.cidr
  vpc_endpoint_id        = local.firewall_endpoints[each.value.az]
}

resource "aws_route_table_association" "hub_public" {
  for_each = local.az_index

  subnet_id      = aws_subnet.hub_public[each.key].id
  route_table_id = aws_route_table.hub_public[each.key].id
}
