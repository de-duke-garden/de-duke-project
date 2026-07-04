variable "environment" { type = string }

variable "visibility_timeout_seconds" {
  type    = number
  default = 60
}

variable "message_retention_seconds" {
  type    = number
  default = 345600 # 4 days
}

variable "dlq_retention_seconds" {
  type    = number
  default = 1209600 # 14 days — max, gives ops time to investigate failed jobs
}

variable "max_receive_count" {
  description = "Number of processing attempts before a message is routed to the DLQ."
  type        = number
  default     = 5
}

variable "tags" {
  type    = map(string)
  default = {}
}
