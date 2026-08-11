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

# MX -- SES inbound (keeps inbound mail flowing after the switch).
variable "mx_record" {
  description = "MX record for the apex domain (value with priority)."
  type        = string
  default     = "10 inbound-smtp.eu-west-1.amazonaws.com."
}

# Root TXT records: SPF + Google site verification.
variable "root_txt_records" {
  description = "TXT records for the apex domain."
  type        = list(string)
  default = [
    "\"v=spf1 include:amazonses.com ~all\"",
    "\"google-site-verification=TDf3Xy_2XQitmbVtdlj41ZHG1orI26gvvyHPJXTtwvE\"",
  ]
}

variable "amazonses_txt" {
  description = "TXT record for _amazonses.de-duke.com (SES domain verification)."
  type        = string
  default     = "\"QLGen14yxyH1pyNcqAuKD/0i7FBdf7hJVecrLLlBx0s=\""
}

variable "dmarc_txt" {
  description = "TXT record for _dmarc.de-duke.com."
  type        = string
  default     = "\"v=DMARC1;p=quarantine;pct=100;fo=1\""
}

# SES DKIM signing CNAMEs (three selectors currently in use).
variable "dkim_cnames" {
  description = "Map of DKIM selector -> amazonses.com target."
  type        = map(string)
  default = {
    "3pi67xi5wux5q5hjxdxkfpe7vft5wgrc" = "3pi67xi5wux5q5hjxdxkfpe7vft5wgrc.dkim.amazonses.com."
    "ba2rg34nvwqalw43or3vchz6zn2apq4t" = "ba2rg34nvwqalw43or3vchz6zn2apq4t.dkim.amazonses.com."
    "chzqkjrm4n5aee5q4cjqlrkxxukcip3i" = "chzqkjrm4n5aee5q4cjqlrkxxukcip3i.dkim.amazonses.com."
  }
}

variable "autodiscover_cname" {
  description = "CNAME target for autodiscover.de-duke.com (Amazon WorkMail)."
  type        = string
  default     = "autodiscover.mail.eu-west-1.awsapps.com."
}

variable "labels" {
  description = "Common GCP resource labels."
  type        = map(string)
  default = {
    project   = "de-duke"
    managedby = "terraform"
  }
}
