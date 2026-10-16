# AWS Network Firewall in the hub VPC.
#
# Policy (strict rule order, default = drop established + alert):
#   - East-west: ICMP and selected TCP ports allowed between spokes.
#   - Egress:    HTTP/HTTPS allowed only to var.allowed_egress_domains (matched on Host / TLS SNI).
#   - Anything else is dropped and logged to the ALERT log group.

locals {
  east_west_ports = join(",", [for p in var.east_west_tcp_ports : tostring(p)])

  egress_rules = flatten([
    for i, d in var.allowed_egress_domains : [
      "pass tls $SPOKES any -> $EXTERNAL_NET 443 (tls.sni; dotprefix; content:\".${d}\"; nocase; endswith; msg:\"Egress TLS to ${d}\"; flow:to_server; sid:${2000 + i * 2}; rev:1;)",
      "pass http $SPOKES any -> $EXTERNAL_NET 80 (http.host; dotprefix; content:\".${d}\"; endswith; msg:\"Egress HTTP to ${d}\"; flow:to_server; sid:${2001 + i * 2}; rev:1;)",
    ]
  ])

  suricata_rules = join("\n", concat(
    [
      "pass icmp $SPOKES any -> $SPOKES any (msg:\"East-west ICMP\"; sid:1000; rev:1;)",
      "pass tcp $SPOKES any -> $SPOKES [${local.east_west_ports}] (msg:\"East-west TCP\"; flow:to_server; sid:1001; rev:1;)",
    ],
    local.egress_rules,
  ))
}

resource "aws_networkfirewall_rule_group" "stateful" {
  name     = "${var.name}-stateful"
  type     = "STATEFUL"
  capacity = 200

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = concat([var.hub_cidr], local.spoke_cidrs)
        }
      }
      ip_sets {
        key = "SPOKES"
        ip_set {
          definition = local.spoke_cidrs
        }
      }
    }

    rules_source {
      rules_string = local.suricata_rules
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = { Name = "${var.name}-stateful" }
}

resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.name}-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_default_actions = ["aws:drop_established", "aws:alert_established"]

    stateful_rule_group_reference {
      priority     = 100
      resource_arn = aws_networkfirewall_rule_group.stateful.arn
    }
  }

  tags = { Name = "${var.name}-policy" }
}

resource "aws_networkfirewall_firewall" "this" {
  name                = "${var.name}-firewall"
  vpc_id              = aws_vpc.hub.id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn

  dynamic "subnet_mapping" {
    for_each = aws_subnet.hub_firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }

  tags = { Name = "${var.name}-firewall" }
}

# --- Logging ---------------------------------------------------------------

resource "aws_cloudwatch_log_group" "firewall_alert" {
  name              = "/${var.name}/network-firewall/alert"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "firewall_flow" {
  name              = "/${var.name}/network-firewall/flow"
  retention_in_days = var.log_retention_days
}

resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    log_destination_config {
      log_type             = "ALERT"
      log_destination_type = "CloudWatchLogs"
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_alert.name
      }
    }

    log_destination_config {
      log_type             = "FLOW"
      log_destination_type = "CloudWatchLogs"
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_flow.name
      }
    }
  }
}
