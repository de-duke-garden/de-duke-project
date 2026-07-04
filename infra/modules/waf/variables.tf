variable "environment" { type = string }
variable "alb_arn" {
  description = "ARN of the Application Load Balancer to protect."
  type        = string
}
variable "rate_limit_per_5min" {
  description = "Max requests per IP per 5-minute window before blocking (edge-level backstop)."
  type        = number
  default     = 2000
}
variable "tags" {
  type    = map(string)
  default = {}
}
