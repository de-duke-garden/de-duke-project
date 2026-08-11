# De-Duke GCP Infrastructure -- provider/version pinning.
# Root-level reference for the GCP tree (infra/gcp/). The AWS tree keeps
# its own versions.tf untouched at infra/versions.tf until cutover.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state in GCS, inside the same GCP project that hosts the infra
  # (de-duke-services). Bucket is created out-of-band (bootstrap step, see
  # README.md) and passed via -backend-config=backend.hcl.
  backend "gcs" {}
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "random" {}

# GCP API activation is asynchronous: google_project_service returns once the
# enable operation is accepted, but the API can still reject calls for ~60s.
# terraform_data.api_propagation (main.tf) forces every API consumer to wait
# out that propagation window.
