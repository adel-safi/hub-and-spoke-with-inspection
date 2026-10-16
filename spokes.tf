module "spoke" {
  source   = "./modules/spoke_vpc"
  for_each = var.spokes

  name               = "${var.name}-${each.key}"
  cidr               = each.value.cidr
  azs                = local.azs
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}
