# De-Duke GCP Infrastructure -- media storage (replaces S3 + CloudFront).
# GCS bucket + Cloud CDN. Cloud CDN on GCP requires a backend bucket attached
# to a global HTTPS load balancer -- so the LB in this file is mandatory for
# the CDN choice (Cloud Armor stays deferred; that is the only deferred part).

# The media bucket (replaces the S3 bucket).
resource "google_storage_bucket" "media" {
  name     = "de-duke-media-${var.media_bucket_suffix}"
  project  = var.gcp_project_id
  location = var.gcp_region

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
  # No public access: the bucket is only reachable through the LB's Cloud CDN
  # (same trust model as the S3 + CloudFront OAC setup).

  labels = local.labels

  depends_on = [terraform_data.api_propagation]
}

# The LB's backend bucket with CDN enabled (replaces CloudFront).
resource "google_compute_backend_bucket" "media_cdn" {
  name        = "de-duke-media-cdn"
  project     = var.gcp_project_id
  description = "De-Duke media CDN (GCS + Cloud CDN)"
  bucket_name = google_storage_bucket.media.name
  enable_cdn  = true

  # CDN cache TTLs mirror the CloudFront default_cache_behavior in
  # infra/modules/s3_cdn (min 0s / default 86400s / max 604800s).
  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    default_ttl                  = 86400
    max_ttl                      = 604800
    client_ttl                   = 0
    serve_while_stale            = 86400
    request_coalescing           = false
    signed_url_cache_max_age_sec = 0
  }

  depends_on = [terraform_data.api_propagation]
}

# Static global IP for the LB -- DNS records point here (api/cdn A records).
resource "google_compute_global_address" "lb" {
  name    = "de-duke-lb-ip"
  project = var.gcp_project_id

  depends_on = [terraform_data.api_propagation]
}

# Managed TLS cert. NOTE: cert provisioning only completes once the domains
# resolve to the LB IP (i.e., after DNS cutover) -- expected pre-cutover.
resource "google_compute_managed_ssl_certificate" "lb" {
  name    = "de-duke-lb-cert"
  project = var.gcp_project_id

  managed {
    domains = compact([local.api_fqdn, local.cdn_fqdn])
  }

  depends_on = [terraform_data.api_propagation]
}

# HTTPS LB fronting both the API backend service and the media CDN backend
# bucket via host-based routing:
#   api.<domain>  -> Cloud Run API  (google_compute_backend_service)
#   cdn.<domain>  -> media bucket   (google_compute_backend_bucket)
resource "google_compute_url_map" "lb" {
  name            = "de-duke-lb"
  project         = var.gcp_project_id
  default_service = google_compute_backend_service.api.id

  host_rule {
    hosts        = [local.api_fqdn]
    path_matcher = "api"
  }
  host_rule {
    hosts        = [local.cdn_fqdn]
    path_matcher = "media"
  }

  path_matcher {
    name            = "api"
    default_service = google_compute_backend_service.api.id
  }
  path_matcher {
    name            = "media"
    default_service = google_compute_backend_bucket.media_cdn.id
  }

  depends_on = [terraform_data.api_propagation]
}

resource "google_compute_target_https_proxy" "lb" {
  name             = "de-duke-lb-proxy"
  project          = var.gcp_project_id
  url_map          = google_compute_url_map.lb.id
  ssl_certificates = [google_compute_managed_ssl_certificate.lb.id]

  depends_on = [terraform_data.api_propagation]
}

resource "google_compute_global_forwarding_rule" "lb" {
  name       = "de-duke-lb-fwd"
  project    = var.gcp_project_id
  target     = google_compute_target_https_proxy.lb.id
  ip_address = google_compute_global_address.lb.address
  port_range = "443"

  depends_on = [terraform_data.api_propagation]
}
