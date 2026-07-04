variable "environment" { type = string }
variable "account_suffix" {
  description = "Unique suffix (e.g. AWS account ID or short hash) to keep the bucket name globally unique."
  type        = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
