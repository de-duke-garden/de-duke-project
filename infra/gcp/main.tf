# De-Duke GCP Infrastructure -- core: enabled APIs, service account, IAM.
# Target project: de-duke-services (already hosts Firestore/Auth/FCM).

# ---------------------------------------------------------------------------
# Enabled APIs. `disable_on_destroy = false` is deliberate: this project is
# shared with Firestore/Firebase, and destroying this infra must never take
# those down. Enabling is idempotent (many are already on).
# ---------------------------------------------------------------------------
locals {
  required_apis = [
    "run.googleapis.com",                  # Cloud Run (API + worker)
    "sqladmin.googleapis.com",             # Cloud SQL for PostgreSQL
    "storage.googleapis.com",              # GCS media bucket
    "pubsub.googleapis.com",               # Task queue
    "secretmanager.googleapis.com",        # Secrets
    "artifactregistry.googleapis.com",     # Container registry
    "dns.googleapis.com",                  # Cloud DNS zone for de-duke.com
    "compute.googleapis.com",              # HTTPS LB + CDN backend bucket
    "cloudscheduler.googleapis.com",       # Hold-expiry / recurring jobs
    "cloudresourcemanager.googleapis.com", # project metadata
  ]
}

resource "google_project_service" "required" {
  for_each                   = toset(local.required_apis)
  project                    = var.gcp_project_id
  service                    = each.key
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Choke point for the async API-activation window. Every resource that calls
# a just-enabled API depends on this data resource (see the depends_on pattern
# used throughout this tree), not directly on the project_service resources.
# Uses the built-in terraform_data (no external provider download needed) with
# a local-exec sleep: "sleep" is a valid command in both bash (CI runners) and
# pwsh (local dev, where it aliases Start-Sleep).
resource "terraform_data" "api_propagation" {
  # Referencing the whole resource map creates the dependency on every
  # project_service instance.
  depends_on = [google_project_service.required]

  # interpreter (not the default shell) so the same command works on Windows
  # cmd and Linux bash CI runners alike; python3 exists on both.
  provisioner "local-exec" {
    interpreter = ["python", "-c"]
    command     = "import time; time.sleep(60)"
  }
}

# ---------------------------------------------------------------------------
# Runtime service account for Cloud Run (API + worker). Replaces the three
# AWS IAM roles (task_execution / task / db_proxy) with one workload
# identity; the Cloud SQL Auth Proxy uses its cloudsql.client role, the
# container uses the rest.
# ---------------------------------------------------------------------------
resource "google_service_account" "backend" {
  account_id   = "de-duke-backend"
  display_name = "De-Duke backend runtime (Cloud Run)"
  project      = var.gcp_project_id
}

# Cloud Run invoker for the API -- public (allUsers) exactly like today's
# public ALB. Cloud Armor (deferred) is the control that later restricts
# this; until then, same trust level as the AWS production ALB.
resource "google_cloud_run_v2_service_iam_member" "api_public" {
  location = var.gcp_region
  project  = var.gcp_project_id
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Run invoker for the worker -- NOT public. Only the backend service
# account (used by Pub/Sub push via OIDC token) may invoke it.
resource "google_cloud_run_v2_service_iam_member" "worker_invoker" {
  location = var.gcp_region
  project  = var.gcp_project_id
  name     = google_cloud_run_v2_service.worker.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.backend.email}"
}

# Cloud SQL client -- lets the Cloud SQL Auth Proxy sidecar connect.
# Cloud SQL IAM (roles/cloudsql.client) is bound at PROJECT level only (no
# instance-scoped IAM resource exists in the provider), so this grant needs
# roles/owner on the project -- the active deploy account (roles/editor)
# cannot set it (see README "credentials" note).
resource "google_project_iam_member" "backend_cloudsql" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

# Secret accessor on both secrets (app secrets + DB credentials).
resource "google_secret_manager_secret_iam_member" "app_secrets" {
  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.app_secrets.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"

  depends_on = [terraform_data.api_propagation]
}

resource "google_secret_manager_secret_iam_member" "db_credentials" {
  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.db_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"

  depends_on = [terraform_data.api_propagation]
}

# Redis URL secret accessor -- the backend reads it as REDIS_URL.
resource "google_secret_manager_secret_iam_member" "redis_url" {
  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.redis_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"

  depends_on = [terraform_data.api_propagation]
}

# Pub/Sub publisher -- the backend enqueues jobs by publishing to the task topic.
resource "google_pubsub_topic_iam_member" "backend_publisher" {
  project = var.gcp_project_id
  topic   = google_pubsub_topic.tasks.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.backend.email}"

  # API enablement must land before the first Pub/Sub IAM grant.
  depends_on = [terraform_data.api_propagation]
}
# Object access to the media bucket (read/write, matching the AWS S3 grants).
resource "google_storage_bucket_iam_member" "backend_media" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backend.email}"

  depends_on = [terraform_data.api_propagation]
}

# Artifact Registry reader -- Cloud Run pulls the backend image from the repo.
resource "google_artifact_registry_repository_iam_member" "backend_reader" {
  project    = var.gcp_project_id
  location   = var.gcp_region
  repository = google_artifact_registry_repository.backend.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.backend.email}"

  depends_on = [terraform_data.api_propagation]
}
