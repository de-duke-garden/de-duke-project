# De-Duke GCP Infrastructure -- GitHub Actions Workload Identity Federation.
# Replaces the AWS OIDC role (github-de-duke-garden) as the CI/CD identity:
# GitHub Actions exchanges its OIDC token for a short-lived GCP credential
# that impersonates the deploy service account. No long-lived keys anywhere.

# ---------------------------------------------------------------------------
# Deploy service account -- the identity the deploy workflow acts as.
# Scoped to exactly what CI needs: deploy Cloud Run services/jobs, push
# images to Artifact Registry, and read the Terraform state bucket.
# ---------------------------------------------------------------------------
resource "google_service_account" "deploy" {
  account_id   = "de-duke-deploy"
  display_name = "De-Duke CI/CD deploy (GitHub Actions)"
  project      = var.gcp_project_id
}

# Cloud Run deployer -- create/update services + jobs (the deploy workflow
# applies the new image tag and runs migrate/bootstrap jobs).
resource "google_project_iam_member" "deploy_run" {
  project = var.gcp_project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Artifact Registry writer -- push the backend image.
resource "google_project_iam_member" "deploy_artifact_writer" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Terraform state bucket access -- the workflow's terraform init/apply reads
# and locks the GCS state bucket (de-duke-services-tfstate).
resource "google_storage_bucket_iam_member" "deploy_tfstate" {
  bucket = "de-duke-services-tfstate"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.deploy.email}"
}

# Allow the deploy identity to run jobs that execute AS the backend runtime
# service account (the migrate + bootstrap jobs use de-duke-backend).
resource "google_service_account_iam_member" "deploy_act_as_backend" {
  service_account_id = google_service_account.backend.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deploy.email}"
}

# ---------------------------------------------------------------------------
# Workload Identity Pool + provider (GitHub OIDC).
# Pool:    projects/<project>/locations/global/workloadIdentityPools/github-actions
# Provider: attribute.repository == de-duke-garden/de-duke-project
# ---------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "OIDC federation for GitHub Actions workflows (de-duke-garden repos)"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.gcp_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "de-duke-project"
  display_name                       = "de-duke-garden/de-duke-project"
  attribute_condition                = "assertion.repository == 'de-duke-garden/de-duke-project'"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allow the repo's main-branch workflows to impersonate the deploy SA.
resource "google_service_account_iam_binding" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    # main-branch deploys (deploy workflow)
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/de-duke-garden/de-duke-project",
  ]
}
