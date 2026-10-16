variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix applied to every resource."
  type        = string
  default     = "hns"
}

variable "az_count" {
  description = "Number of Availability Zones to span (one firewall endpoint and NAT gateway per AZ)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 4
    error_message = "az_count must be between 1 and 4."
  }
}

variable "hub_cidr" {
  description = "CIDR of the hub (inspection + egress) VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "spokes" {
  description = "Spoke VPCs to create, keyed by short name."
  type = map(object({
    cidr = string
  }))
  default = {
    spoke-a = { cidr = "10.1.0.0/16" }
    spoke-b = { cidr = "10.2.0.0/16" }
  }
}

variable "internal_supernet" {
  description = "Summary route covering all spoke CIDRs; traffic to it is sent back to the Transit Gateway after inspection."
  type        = string
  default     = "10.0.0.0/8"
}

variable "allowed_egress_domains" {
  description = "Domains (and their subdomains) spokes may reach over HTTP/HTTPS. Everything else to the internet is dropped."
  type        = list(string)
  default = [
    "amazonaws.com",
    "amazon.com",
  ]
}

variable "east_west_tcp_ports" {
  description = "TCP ports allowed between spokes (ICMP is always allowed between spokes)."
  type        = list(number)
  default     = [22, 80, 443]
}

variable "create_test_instances" {
  description = "Launch one small SSM-managed EC2 instance per spoke for testing traffic flows."
  type        = bool
  default     = true
}

variable "test_instance_type" {
  description = "Instance type for the test instances."
  type        = string
  default     = "t3.micro"
}

variable "log_retention_days" {
  description = "Retention for Network Firewall CloudWatch log groups."
  type        = number
  default     = 14
}
