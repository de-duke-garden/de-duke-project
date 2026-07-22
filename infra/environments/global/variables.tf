variable "aws_region" {
  description = "Must match every environment's ALB region -- ACM certs used by an ALB listener must be issued in the same region as the ALB itself."
  type        = string
  default     = "eu-west-1"
}

variable "domain_name" {
  description = "Root domain of the existing, externally-managed Route53 hosted zone. Referenced as a data source (not imported) so Terraform never has the ability to delete or recreate the zone -- see main.tf's data \"aws_route53_zone\" block."
  type        = string
  default     = "de-duke.com"
}
