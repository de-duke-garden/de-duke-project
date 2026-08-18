# De-Duke GCP Infrastructure -- input variables.
# Minimal, launch-scoped footprint per infra/gcp/README.md (proposal).
# Defaults are the cost-minimizing choices confirmed with the operator;
# override in terraform.tfvars for anything that must differ.

variable "gcp_project_id" {
  description = "GCP project hosting the migrated backend (and already Firestore/Auth/FCM)."
  type        = string
}

variable "gcp_project_number" {
  description = "GCP project NUMBER (not ID) -- used to address the Cloud CDN fetch service account (service-<number>@https-lb.iam.gserviceaccount.com), which the media bucket grants roles/storage.objectViewer so the LB's backend bucket can serve objects through Cloud CDN."
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

variable "admin_console_url" {
  description = "Public origin of the Admin Web Console (used for staff invite links)."
  type        = string
  default     = "https://admin.de-duke.com"
}

variable "marketing_site_url" {
  description = "Public origin of the Marketing Site (used for Paystack callback + share links)."
  type        = string
  default     = "https://de-duke.com"
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

# Root TXT records: SPF (Zoho mailboxes + Zepto transactional) + Google site
# verification + Zoho domain verification.
variable "root_txt_records" {
  description = "TXT records for the apex domain."
  type        = list(string)
  default = [
    "\"v=spf1 include:zohomail.com include:zeptomail.net ~all\"",
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

# Zoho DKIM TXT value (v=DKIM1; k=rsa; p=...). 1024-bit key -- fits a single
# <=255-char TXT string, which Zoho's checker accepts (the earlier 2048-bit
# key exceeded the limit and had to be split, which their checker rejected).
variable "zoho_dkim_txt" {
  description = "Zoho DKIM TXT value."
  type        = string
  default     = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCQIN+Mrf0RjA5CpHN5pEed3zUHqwSW0t022X3W/mJWXqUTJuICKyzVmAWDUS1+PwIElJ8BHQ1IGnKoJmVcV1AK61tXiXGJEAbbQN7EfflwQxFQl8cBCbI/OeJEyT2E558qmBROYx1HPVJOLAouzXlOA0Ds8aBrYOH5E88PEqWfLwIDAQAB"
}

# ---------------------------------------------------------------------------
# ZeptoMail (transactional, noreply@) -- 1024-bit DKIM (fits a single TXT
# string) + return-path CNAME on the `send` subdomain.
# ---------------------------------------------------------------------------
variable "zepto_dkim_host" {
  description = "ZeptoMail DKIM host (<selector>._domainkey.send)."
  type        = string
  default     = "1110642._domainkey.send"
}

variable "zepto_dkim_txt" {
  description = "ZeptoMail DKIM TXT value."
  type        = string
  default     = "k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCG1JLXCEF/8PmuFpMNw7lmN9kGBsB+Pqt//NU4R9xADHaoZFEWeWtE3b5WbLbp9yzQP2FQGFyhSScqbubH0+wsaCx/AhNJRdlpUs8Ucs4D6Lw4/TRzQFhaTdV2/6plTh9yxg/GGsDVM4vrXc2s2B4StGBXb+5eA4dp03jv2BzI2QIDAQAB"
}

variable "zepto_bounce_host" {
  description = "ZeptoMail return-path CNAME host (bounce.<subdomain>)."
  type        = string
  default     = "bounce-zem.send"
}

variable "zepto_bounce_cname" {
  description = "ZeptoMail return-path CNAME target."
  type        = string
  default     = "cluster89.zeptomail.com."
}

variable "labels" {
  description = "Common GCP resource labels."
  type        = map(string)
  default = {
    project   = "de-duke"
    managedby = "terraform"
  }
}
