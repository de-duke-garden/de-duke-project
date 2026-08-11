# De-Duke GCP Infrastructure -- input variables.
# Minimal, launch-scoped footprint per infra/gcp/README.md (proposal).
# Defaults are the cost-minimizing choices confirmed with the operator;
# override in terraform.tfvars for anything that must differ.

variable "gcp_project_id" {
  description = "GCP project hosting the migrated backend (and already Firestore/Auth/FCM)."
  type        = string
}

variable "gcp_region" {
  description = "Region closest to the primary Nigerian user base with GCP services (README proposal)."
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Deploy environment name; production is the only one (no staging on GCP)."
  type        = string
  default     = "production"
}

variable "image_tag" {
  description = "Tag of the real backend image in Artifact Registry to deploy to Cloud Run. Empty = placeholder image (nginx) so the first apply works before CI has ever pushed."
  type        = string
  default     = ""
}

variable "cloud_sql_tier" {
  description = "Cloud SQL shared-core tier for the primary database. db-f1-micro is the cheapest; db-g1-small doubles RAM for PostGIS+pgvector headroom. NOTE: Cloud SQL free tier is US-region-only, not available in europe-west1."
  type        = string
  default     = "db-g1-small"
}

variable "cloud_sql_disk_gb" {
  description = "Primary database disk size (GB). PostGIS+pgvector grow; 20 GB matches the current AWS footprint."
  type        = number
  default     = 20
}

variable "cloud_sql_disk_type" {
  description = "Primary database disk type. PD_SSD is the default for Cloud SQL Postgres."
  type        = string
  default     = "PD_SSD"
}

variable "media_bucket_suffix" {
  description = "Short unique suffix for the globally-unique GCS media bucket name (e.g. your GCP project number or a short hash)."
  type        = string
}

variable "cdn_domain" {
  description = "Public hostname for the media CDN. Empty until the Cloud DNS zone is authoritative / cutover is ready."
  type        = string
  default     = ""
}

variable "api_domain" {
  description = "Public hostname for the API. Empty until the Cloud DNS zone is authoritative / cutover is ready."
  type        = string
  default     = ""
}

variable "admin_fqdn" {
  description = "Admin Web Console hostname (Vercel-hosted, DNS-only record)."
  type        = string
  default     = ""
}

variable "vercel_cname_target" {
  description = "CNAME target Vercel gives for the Admin Web Console."
  type        = string
  default     = ""
}

variable "marketing_fqdn" {
  description = "Marketing site apex hostname (Vercel-hosted, DNS-only record)."
  type        = string
  default     = ""
}

variable "vercel_apex_ips" {
  description = "IP(s) Vercel gives for the marketing site apex. Vercel expanded its IP range and recommends 216.198.79.1 over the legacy 76.76.21.21 (which still works but is deprecated)."
  type        = list(string)
  default     = ["216.198.79.1"]
}

variable "marketing_www_fqdn" {
  description = "www hostname for the Marketing Site (Vercel's primary domain)."
  type        = string
  default     = ""
}

variable "vercel_marketing_cname_target" {
  description = "CNAME target Vercel gives for the Marketing Site's www hostname."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Apex domain for the Cloud DNS zone (de-duke.com)."
  type        = string
  default     = "de-duke.com"
}

variable "api_min_instances" {
  description = "Cloud Run minimum instances for the API. 0 = scale to zero (cost-minimizing)."
  type        = number
  default     = 0
}

variable "api_max_instances" {
  description = "Cloud Run maximum instances for the API."
  type        = number
  default     = 10
}

variable "api_cpu" {
  description = "Cloud Run CPU allocation for the API (vCPU). 1 matches the current Fargate task."
  type        = string
  default     = "1"
}

variable "api_memory" {
  description = "Cloud Run memory allocation for the API (e.g. 512Mi, 1Gi, 2Gi)."
  type        = string
  default     = "1Gi"
}

variable "worker_min_instances" {
  description = "Cloud Run minimum instances for the worker. 0 = scale to zero (cost-minimizing)."
  type        = number
  default     = 0
}

variable "worker_max_instances" {
  description = "Cloud Run maximum instances for the worker."
  type        = number
  default     = 5
}

variable "worker_cpu" {
  description = "Cloud Run CPU allocation for the worker (vCPU)."
  type        = string
  default     = "1"
}

variable "worker_memory" {
  description = "Cloud Run memory allocation for the worker."
  type        = string
  default     = "1Gi"
}

variable "paystack_fallback_email" {
  description = "Plain (non-secret) fallback email for Paystack checkout (mirrors the AWS task env var)."
  type        = string
  default     = "info@de-duke.com"
}

variable "hold_expiry_cron" {
  description = "Cloud Scheduler cron for the hold-expiry sweep job (mirrors the AWS Background Task Processor's recurring job)."
  type        = string
  default     = "*/5 * * * *"
}

# ---------------------------------------------------------------------------
# DNS records mirrored from the live Route53 zone (de-duke.com, Z0515278P16TK8J7UPOF)
# at cutover-planning time. These keep email (SES/WorkMail) and verification
# working after the nameserver switch. Override in terraform.tfvars if the
# email provider changes (the SES keep-vs-replace decision is still open).
# The ACM validation CNAME (_cda1e1...) is deliberately NOT mirrored -- it
# validates an AWS cert that does not exist on GCP (Google-managed certs).
# ---------------------------------------------------------------------------

# MX -- Zoho Mail (mailboxes for info/hello/legal@de-duke.com).
variable "mx_records" {
  description = "MX records for the apex domain (priority + host, per Zoho's setup wizard)."
  type        = list(string)
  default = [
    "10 mx.zoho.com.",
    "20 mx2.zoho.com.",
    "50 mx3.zoho.com.",
  ]
}

# Root TXT records: Zoho SPF + Google site verification + Zoho domain verification.
# Transactional provider (Zepto/Resend) SPF include + DKIM get added here once
# the provider is chosen and its records are provided.
variable "root_txt_records" {
  description = "TXT records for the apex domain."
  type        = list(string)
  default = [
    "\"v=spf1 include:zohomail.com ~all\"",
    "\"google-site-verification=TDf3Xy_2XQitmbVtdlj41ZHG1orI26gvvyHPJXTtwvE\"",
    "\"zoho-verification=zb48910551.zmverify.zoho.com\"",
  ]
}

variable "dmarc_txt" {
  description = "TXT record for _dmarc.de-duke.com."
  type        = string
  default     = "\"v=DMARC1;p=quarantine;pct=100;fo=1\""
}

# Zoho Mail DKIM -- TXT record for the generated selector (2048-bit key).
variable "zoho_dkim_selector" {
  description = "Zoho DKIM selector (the <selector>._domainkey prefix)."
  type        = string
  default     = "zoho"
}

# Zoho DKIM TXT value (v=DKIM1; k=rsa; p=...). Split into two <=255-char
# quoted strings (DNS TXT per-string limit); concatenated by validators.
variable "zoho_dkim_txt" {
  description = "Zoho DKIM TXT value, split into 255-char chunks (list of quoted strings)."
  type        = list(string)
  default = [
    "\"v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqdylVcf7d8VASNMKQGZwLjmaM2bxyaBUvEckVKpnsFcJp2scDW2UMIUBYZ+mnDnyxeG7kZQm71p4CKGYJLGi9/Py6Jykuw+EKvS1R6poDYAPfwav0i/eMac7dKq/TPdZzi0Wd91LbJg+8dWOn1ADRUrSM4y45LcpnrqOyHI0xbwQHAeabs6Hq9Y4TOfNsbbg1\"",
    "\"wrr54pBwdVWHq9oSWKO2X0KdLKuMydlIrcM94ngmSb0+slPJ/+AQE7P/AKNarjPJ4eBeLmK2GvYs6OUCXwNGWbQyCtrIuOXAl5IraNFxF9q+HezpUHd+wt2Cm9Pux99PZ8R79ldNzg7bfj6ut6CMwIDAQAB\"",
  ]
}

variable "labels" {
  description = "Common GCP resource labels."
  type        = map(string)
  default = {
    project   = "de-duke"
    managedby = "terraform"
  }
}
