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
  #
  # public_access_prevention = "enforced" is what makes that invariant real
  # rather than a comment. GCS rejects any allUsers / allAuthenticatedUsers
  # grant on a PAP-enforced bucket at the API level, so a public binding added
  # out of band (console, gcloud, a stray script) fails instead of silently
  # opening the bucket. It is deliberately NOT expressed as an authoritative
  # google_storage_bucket_iam_binding: GCS materialises ACL-derived legacy
  # bindings on this bucket (projectViewer -> legacyObjectReader etc.), and an
  # authoritative binding for any of those roles would strip them and have them
  # re-added by GCS on the next read -- a perpetual diff that also revokes
  # project-viewer read access. PAP plus the least-privilege reader grant in
  # main.tf (cdn_fetch_media) cover the same invariant without that trap.
  #
  # Verified 2026-11-13: the bucket itself is private (anonymous
  # storage.googleapis.com/de-duke-media-531781610440 returns 403 for both the
  # object and the bucket-listing forms, and the project has no allUsers storage
  # binding anywhere). The key enumeration that answered at
  # https://cdn.de-duke.org/ came from the CDN fetch service account's
  # roles/storage.objectViewer, which carries storage.objects.list -- the LB
  # proxies the anonymous request to GCS as that service account. That role is
  # now downgraded to get-only; see main.tf.
  public_access_prevention = "enforced"

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
  # infra/modules/s3_cdn (min 0s / default 86400s), except for the maximum and
  # client TTLs, which are widened to the immutable media lifetime.
  #
  # How caching actually resolves here (the policy alone cannot fix it):
  # cache_mode CACHE_ALL_STATIC means Cloud CDN respects the origin's
  # Cache-Control, and it never caches a response that says `private`. GCS
  # serves an object with NO cache metadata as `Cache-Control: private,
  # max-age=0`, so every media request was an origin hit no matter what these
  # TTLs say. The blocker is object metadata, not this policy: objects must
  # carry `Cache-Control: public, max-age=31536000, immutable` (see
  # infra/scripts/fix_media_object_metadata.py). Once they do:
  #   - max_ttl is the hard ceiling CACHE_ALL_STATIC will honour, so it must be
  #     at least the object's max-age or the one-year header is silently
  #     truncated (604800 capped media at 7 days);
  #   - client_ttl clamps the max-age sent DOWNSTREAM to browsers and can only
  #     lower it, never raise it. At 0 it pinned every media response to
  #     `max-age=0` for clients, so browsers re-fetched on every view even with
  #     a correct origin header.
  # Cloud CDN additionally treats an edge expiration beyond 30 days as 30 days
  # internally; that is its own cap, and it still forwards the accurate max-age
  # to clients, so one year stays correct at the browser.
  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    default_ttl                  = 86400
    max_ttl                      = 31536000
    client_ttl                   = 31536000
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

# Legacy .com managed TLS cert. Kept attached to the proxy so the old domain
# keeps serving if its registration is recovered. Never destroy this while the
# proxy still references it.
resource "google_compute_managed_ssl_certificate" "lb" {
  name    = "de-duke-lb-cert"
  project = var.gcp_project_id

  managed {
    domains = compact([var.legacy_api_domain, var.legacy_cdn_domain])
  }

  depends_on = [terraform_data.api_propagation]
}

# New .org managed TLS cert. Provisioning only completes once
# api.de-duke.org and cdn.de-duke.org resolve to the LB IP, so it stays
# PROVISIONING until DNS propagates.
resource "google_compute_managed_ssl_certificate" "lb_org" {
  name    = "de-duke-lb-cert-org"
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
  name    = "de-duke-lb-proxy"
  project = var.gcp_project_id
  url_map = google_compute_url_map.lb.id
  # Both certs stay attached: .com for recovery, .org as the live primary.
  ssl_certificates = [
    google_compute_managed_ssl_certificate.lb.id,
    google_compute_managed_ssl_certificate.lb_org.id,
  ]

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
