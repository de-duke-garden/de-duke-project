variable "aws_region" {
  description = "AWS region the state bucket lives in. Should match every environment's aws_region."
  type        = string
}

variable "aws_account_suffix" {
  description = "Short, unique suffix (e.g. AWS account ID) to make the globally-unique bucket name collision-free."
  type        = string
}
