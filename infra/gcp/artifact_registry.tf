# De-Duke GCP Infrastructure -- Artifact Registry (replaces ECR).

resource "google_artifact_registry_repository" "backend" {
  location      = var.gcp_region
  repository_id = "de-duke-backend"
  description   = "De-Duke backend API image"
  format        = "DOCKER"

  labels = local.labels

  depends_on = [terraform_data.api_propagation]
}
