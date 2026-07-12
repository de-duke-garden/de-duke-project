locals {
  common_tags = {
    Project     = "de-duke"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
