# De-Duke GCP Infrastructure -- locals and shared references.

locals {
  # Single label set for every GCP resource in this tree.
  labels = merge(var.labels, {
    environment = var.environment
  })

  # Artifact Registry image reference. Empty image_tag -> the public nginx
  # placeholder so a first apply works before CI has ever pushed (same
  # pattern as infra/modules/fargate_service).
  # Format: <region>-docker.pkg.dev/<project>/<repo>/<image>:<tag>
  backend_image = var.image_tag != "" ? "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/de-duke-backend/backend-api:${var.image_tag}" : "nginx:latest"

  # The Cloud SQL connection name used by the Cloud SQL Auth Proxy sidecar:
  # <project>:<region>:<instance-id>.
  db_connection_name = "${var.gcp_project_id}:${var.gcp_region}:de-duke-primary"

  # Public hostnames this infra serves. api/cdn only when cutover-ready vars
  # are supplied; admin/marketing always mirrored from the AWS dns module.
  api_fqdn     = var.api_domain != "" ? var.api_domain : ""
  cdn_fqdn     = var.cdn_domain != "" ? var.cdn_domain : ""
  admin_fqdn   = var.admin_fqdn != "" ? var.admin_fqdn : ""
  mkt_fqdn     = var.marketing_fqdn != "" ? var.marketing_fqdn : ""
  mkt_www_fqdn = var.marketing_www_fqdn != "" ? var.marketing_www_fqdn : ""

  has_custom_domains = local.api_fqdn != "" || local.cdn_fqdn != ""
}
