variable "environment" {
  description = "Environment name (development, staging, production)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Map of AZ name -> { public_cidr, private_cidr }. Must contain at least 2 entries (Multi-AZ requirement, architecture.md)."
  type = map(object({
    public_cidr  = string
    private_cidr = string
  }))
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}
