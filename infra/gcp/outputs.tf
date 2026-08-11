# De-Duke GCP Infrastructure -- outputs.

output "api_service_url" {
  description = "Cloud Run API service URL (pre-cutover, *.run.app)."
  value       = google_cloud_run_v2_service.api.uri
}

output "worker_service_url" {
  description = "Cloud Run worker service URL (pre-cutover, *.run.app)."
  value       = google_cloud_run_v2_service.worker.uri
}

output "sql_instance_connection_name" {
  description = "Cloud SQL connection name (project:region:instance), for the proxy sidecar."
  value       = google_sql_database_instance.primary.connection_name
}

output "sql_public_ip" {
  description = "Cloud SQL public IP (proxy-only access; no authorized networks)."
  value       = google_sql_database_instance.primary.public_ip_address
}

output "media_bucket_name" {
  description = "GCS media bucket name (MEDIA_BUCKET_NAME for the backend)."
  value       = google_storage_bucket.media.name
}

output "lb_ip_address" {
  description = "Static IP the api/cdn DNS records point at (cutover)."
  value       = google_compute_global_address.lb.address
}

output "tasks_topic" {
  description = "Pub/Sub task queue topic."
  value       = google_pubsub_topic.tasks.name
}

output "artifact_registry_repo" {
  description = "Artifact Registry repo the CI/CD pushes the backend image to."
  value       = google_artifact_registry_repository.backend.name
}

output "dns_nameservers" {
  description = "Cloud DNS nameservers for de-duke.com -- set these at the registrar at cutover."
  value       = google_dns_managed_zone.deduke.name_servers
}
