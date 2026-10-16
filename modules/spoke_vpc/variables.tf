variable "name" {
  description = "Name prefix for the spoke's resources."
  type        = string
}

variable "cidr" {
  description = "CIDR of the spoke VPC."
  type        = string
}

variable "azs" {
  description = "Availability Zones to create subnets in."
  type        = list(string)
}

variable "transit_gateway_id" {
  description = "Transit Gateway to attach the spoke to."
  type        = string
}
