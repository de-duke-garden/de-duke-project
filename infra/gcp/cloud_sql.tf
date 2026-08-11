# De-Duke GCP Infrastructure -- Cloud SQL for PostgreSQL (replaces RDS).
# PostGIS + pgvector are both natively supported by Cloud SQL Postgres via
# CREATE EXTENSION (same as RDS) -- no special database_flags needed.
# Postgres 16 to match the current AWS engine version.

resource "google_sql_database_instance" "primary" {
  name             = "de-duke-primary"
  project          = var.gcp_project_id
  region           = var.gcp_region
  database_version = "POSTGRES_16"

  settings {
    # Edition must be ENTERPRISE for shared-core tiers (db-f1-micro /
    # db-g1-small); the provider default (ENTERPRISE_PLUS) only accepts
    # db-perf-optimized-N-* tiers and rejects db-g1-small with a 400.
    edition = "ENTERPRISE"

    tier              = var.cloud_sql_tier
    disk_size         = var.cloud_sql_disk_gb
    disk_type         = var.cloud_sql_disk_type
    availability_type = "ZONAL" # single-zone; no Multi-AZ standby pre-launch (cost)

    ip_configuration {
      # Public IP, but no authorized networks -- the ONLY path in is the
      # Cloud SQL Auth Proxy sidecar (IAM-authorized, TLS). Equivalent trust
      # to AWS's private-subnet RDS with the RDS Proxy in front.
      ipv4_enabled    = true
      ssl_mode        = "ENCRYPTED_ONLY"
      private_network = null
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = false # PITR disabled pre-launch (cost)
      transaction_log_retention_days = 1
    }

    # Deletion protection ON for production parity with the AWS RDS module.
    deletion_protection_enabled = true
  }

  # depends_on: Cloud SQL Admin API must be enabled before instance creation.
  depends_on = [terraform_data.api_propagation]
}

resource "google_sql_database" "deduke" {
  name     = "deduke"
  instance = google_sql_database_instance.primary.name
  project  = var.gcp_project_id
}

resource "google_sql_user" "app" {
  name     = "deduke_app"
  instance = google_sql_database_instance.primary.name
  project  = var.gcp_project_id
  password = random_password.db.result
}
