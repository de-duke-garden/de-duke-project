# De-Duke GCP Infrastructure -- Pub/Sub task queue (replaces SQS + DLQ) and
# Cloud Scheduler (replaces the hold-expiry recurring job).

# Main task queue topic.
resource "google_pubsub_topic" "tasks" {
  name    = "de-duke-tasks"
  project = var.gcp_project_id

  message_retention_duration = "604800s" # 7 days, mirroring SQS retention

  depends_on = [terraform_data.api_propagation]
}

# Dead-letter topic (replaces the SQS DLQ).
resource "google_pubsub_topic" "tasks_dlq" {
  name    = "de-duke-tasks-dlq"
  project = var.gcp_project_id

  depends_on = [terraform_data.api_propagation]
}

# Push subscription delivering to the worker Cloud Run service. The worker
# endpoint contract (HTTP POST handler) is an app-side wiring item at cutover;
# the infra side (topic -> push -> Cloud Run) is complete.
resource "google_pubsub_subscription" "worker" {
  name    = "de-duke-tasks-worker"
  project = var.gcp_project_id
  topic   = google_pubsub_topic.tasks.id

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = google_cloud_run_v2_service.worker.uri
    oidc_token {
      service_account_email = google_service_account.backend.email
      audience              = google_cloud_run_v2_service.worker.uri
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.tasks_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  depends_on = [terraform_data.api_propagation]
}

# Recurring hold-expiry sweep (risk_log.md R-019 / architecture.md Background
# Task Processor). Publishes to the task topic; the worker consumes it.
resource "google_cloud_scheduler_job" "hold_expiry" {
  name      = "de-duke-hold-expiry"
  project   = var.gcp_project_id
  region    = var.gcp_region
  schedule  = var.hold_expiry_cron
  time_zone = "Africa/Lagos"

  pubsub_target {
    topic_name = google_pubsub_topic.tasks.id
    data       = base64encode("hold_expiry_sweep")
  }

  depends_on = [terraform_data.api_propagation]
}
