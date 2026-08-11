# De-Duke GCP Infrastructure -- Secret Manager.
# Mirrors the AWS secrets module: one JSON blob of application secrets seeded
# with REPLACE_ME (operator populates real values in the console after apply),
# plus a separate DB credentials secret auto-generated here.

# Application secrets -- same JSON contract as infra/modules/secrets/main.tf,
# consumed by the backend via APP_SECRETS (app/core/config.py).
resource "google_secret_manager_secret" "app_secrets" {
  secret_id = "de-duke-app-secrets"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  # API enablement must land before the first secret is created.
  depends_on = [terraform_data.api_propagation]
}

resource "google_secret_manager_secret_version" "app_secrets" {
  secret = google_secret_manager_secret.app_secrets.id

  secret_data = jsonencode({
    PAYSTACK_SECRET_KEY           = "REPLACE_ME"
    PAYSTACK_PUBLIC_KEY           = "REPLACE_ME"
    GOOGLE_MAPS_API_KEY           = "REPLACE_ME"
    FIREBASE_SERVICE_ACCOUNT_JSON = "REPLACE_ME"
    FIRESTORE_PROJECT_ID          = "REPLACE_ME"
    AWS_SES_SENDER_EMAIL          = "REPLACE_ME" # SES decision pending (README)
    SENTRY_DSN                    = "REPLACE_ME"
    ANALYTICS_WRITE_KEY           = "REPLACE_ME"
    JWT_SIGNING_SECRET            = "REPLACE_ME"
    GEMINI_API_KEY                = "REPLACE_ME"
  })
}

# Database credentials -- auto-generated password, stored as the same
# {"username","password"} JSON contract the backend's DB_CREDENTIALS expects.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "de-duke-db-credentials"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  depends_on = [terraform_data.api_propagation]
}

resource "google_secret_manager_secret_version" "db_credentials" {
  secret = google_secret_manager_secret.db_credentials.id

  secret_data = jsonencode({
    username = google_sql_user.app.name
    password = random_password.db.result
  })
}

# Upstash Redis connection string (replaces the deferred GCP Memorystore).
# The backend reads this via REDIS_URL (config.py's redis_url field) for
# refresh tokens, rate-limit counters, and the semantic-search cache.
#
# Seeded with a REPLACE_ME placeholder like every other app secret -- the
# REAL value is populated by an operator via gcloud (see infra/gcp/README.md
# "Secrets" section). Never put the actual Upstash token in this file.
resource "google_secret_manager_secret" "redis_url" {
  secret_id = "de-duke-redis-url"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  depends_on = [terraform_data.api_propagation]
}

resource "google_secret_manager_secret_version" "redis_url" {
  secret = google_secret_manager_secret.redis_url.id

  secret_data = "REPLACE_ME"
}
