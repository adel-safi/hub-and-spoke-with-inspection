# Optional: one SSM-managed instance per spoke to exercise east-west and egress paths.
# Session Manager reaches the instances through the firewall (ssm*.amazonaws.com is on the allow-list),
# so no bastion, public IP or inbound SSH is needed.

locals {
  test_spokes = var.create_test_instances ? var.spokes : {}
}

data "aws_ssm_parameter" "al2023" {
  count = var.create_test_instances ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_iam_role" "test_instance" {
  count = var.create_test_instances ? 1 : 0

  name = "${var.name}-test-instance"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "test_instance_ssm" {
  count = var.create_test_instances ? 1 : 0

  role       = aws_iam_role.test_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "test_instance" {
  count = var.create_test_instances ? 1 : 0

  name = "${var.name}-test-instance"
  role = aws_iam_role.test_instance[0].name
}

resource "aws_security_group" "test_instance" {
  for_each = local.test_spokes

  name        = "${var.name}-${each.key}-test"
  description = "Test instance: allow ICMP and east-west TCP from internal range"
  vpc_id      = module.spoke[each.key].vpc_id

  ingress {
    description = "ICMP from internal range"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.internal_supernet]
  }

  dynamic "ingress" {
    for_each = var.east_west_tcp_ports
    content {
      description = "TCP ${ingress.value} from internal range"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.internal_supernet]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-${each.key}-test" }
}

resource "aws_instance" "test" {
  for_each = local.test_spokes

  ami                    = data.aws_ssm_parameter.al2023[0].value
  instance_type          = var.test_instance_type
  subnet_id              = module.spoke[each.key].workload_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.test_instance[each.key].id]
  iam_instance_profile   = aws_iam_instance_profile.test_instance[0].name

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${var.name}-${each.key}-test" }

  # Instances need the egress path through the firewall in place to register with SSM.
  depends_on = [
    aws_ec2_transit_gateway_route_table_association.spoke,
    aws_ec2_transit_gateway_route.spokes_default_to_hub,
    aws_route.hub_tgw_to_firewall,
    aws_route.hub_firewall_to_nat,
    aws_route.hub_public_to_firewall,
  ]
}
