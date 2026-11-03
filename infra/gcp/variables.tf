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
  description = "Apex of the NEW primary de-duke.org Cloud DNS zone. The legacy de-duke.com zone is managed separately and pinned by the legacy_* variables."
  type        = string
  default     = "de-duke.org"
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
  default     = "info@de-duke.org"
}

variable "admin_console_url" {
  description = "Public origin of the Admin Web Console (used for staff invite links)."
  type        = string
  default     = "https://admin.de-duke.org"
}

variable "marketing_site_url" {
  description = "Public origin of the Marketing Site (used for Paystack callback + share links)."
  type        = string
  default     = "https://de-duke.org"
}

variable "hold_expiry_cron" {
  description = "Cloud Scheduler cron for the hold-expiry sweep job (mirrors the AWS Background Task Processor's recurring job)."
  type        = string
  default     = "*/5 * * * *"
}

# ---------------------------------------------------------------------------
# DNS records for the NEW primary domain, de-duke.org.
#
# de-duke.org is a new zone (its records are sourced from the provider
# dashboards, not copied from the legacy .com zone). The legacy de-duke.com
# zone is separate and is preserved by dns.tf, with its inputs pinned under
# the "Legacy de-duke.com zone inputs" block below.
#   - Zoho Mail             -> MX hosts, SPF include, domain-verification TXT,
#                              DKIM selector/value
#   - ZeptoMail             -> send-subdomain DKIM host/value, bounce CNAME
#   - Google Search Console -> site-verification TXT (only if DNS verification
#                              is used; the HTML/analytics methods need no record)
#
# MX hosts and the SPF include are provider-generic and safe to default. Every
# other value is domain-specific and defaults to "" (or is omitted) so nothing
# invalid can be created: the records in dns.tf are count-guarded and appear
# only once the operator supplies the real values. Do NOT invent these values.
#
# Deliberately absent: the old ACM validation CNAME -- it validated an AWS
# certificate that does not exist on GCP (Google-managed certs are used here).
# ---------------------------------------------------------------------------

# MX -- Zoho Mail (mailboxes for info/hello/legal@de-duke.org).
variable "mx_records" {
  description = "MX records for the apex domain (priority + host, per Zoho's setup wizard)."
  type        = list(string)
  default = [
    "10 mx.zoho.com.",
    "20 mx2.zoho.com.",
    "50 mx3.zoho.com.",
  ]
}

# Root TXT records. SPF only by default: the SPF policy is domain-agnostic and
# covers both Zoho mailboxes and Zepto transactional mail.
# TODO(operator): new Google Search Console and Zoho verification tokens must
# be supplied per environment (terraform.tfvars) BEFORE apply. The old .com
# tokens are invalid for .org; they are preserved for the legacy .com zone in
# legacy_root_txt_records rather than reused here.
variable "root_txt_records" {
  description = "TXT records for the apex domain."
  type        = list(string)
  default = [
    "\"v=spf1 include:zohomail.com include:zeptomail.net ~all\"",
    "\"zoho-verification=zb41521471.zmverify.zoho.com\"",
  ]
}

variable "dmarc_txt" {
  description = "TXT record for _dmarc.de-duke.org."
  type        = string
  default     = "\"v=DMARC1;p=quarantine;pct=100;fo=1\""
}

# Zoho Mail DKIM -- TXT record for the generated selector (2048-bit key).
variable "zoho_dkim_selector" {
  description = "Zoho DKIM selector (the <selector>._domainkey prefix)."
  type        = string
  default     = "zmail"
}

# Zoho DKIM TXT value (v=DKIM1; k=rsa; p=...). Domain-specific: it is issued
# by the Zoho Mail admin console for de-duke.org. Empty by default so the
# record is not created until the operator supplies it (count-guarded in
# dns.tf). 1024-bit keys fit a single <=255-char TXT string, which Zoho's
# checker accepts (a 2048-bit key exceeds the limit and must be split, which
# their checker rejected).
variable "zoho_dkim_txt" {
  description = "Zoho DKIM TXT value for de-duke.org (from the Zoho dashboard). Empty = record not created."
  type        = string
  default     = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCETSachjB9xEAWO9I2QwAWEskAr1QE60UPHTRYV2ozgbLxGwG/ryKpRZEnz7kULfpsCOBTFHoVyk36LMXVZANUn43wn+M91SbmeM9+1CEtcmGID0/hGQrW3x8YiGO3l9EPkDBkjyMFsY6uwKbvypdPOh+XdUigqb/mQU0Q6NBU2wIDAQAB"
}

# ---------------------------------------------------------------------------
# ZeptoMail (transactional, noreply@) -- DKIM TXT + return-path CNAME on the
# `send` subdomain. All values are issued per domain by ZeptoMail; empty
# defaults mean the records are simply not created until supplied.
# ---------------------------------------------------------------------------
variable "zepto_dkim_host" {
  description = "ZeptoMail DKIM host (<selector>._domainkey.send) from the ZeptoMail dashboard. Empty = record not created."
  type        = string
  default     = "39534._domainkey.send"
}

variable "zepto_dkim_txt" {
  description = "ZeptoMail DKIM TXT value from the ZeptoMail dashboard. Empty = record not created."
  type        = string
  default     = "k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyee/RGluoS+Fr5gkAytPwn5+LyQLNEMY6ovs1HIXt1Az+wQWT+k+6OQdmsnudwju/4tCPnGfJHg1rBL69ojy5zENxZPGq37xOa4OArTL9vwIQ8/3inUI816mFGLLyfjlIQHFyv+2ZLnBOmhtGIxS+zJlcwMKxOUd3nNSowIqX4z6btfyT8WvPtKE+W5q6TEEelextLL7cCn1ndvqwLYtwJWWz7q86UrJBXyNyN3dsz3t2mDPKRZm2wiHsPmnEKYRVuwa8QHa1d7KjCyxt5QRdU+D8kaFxqpVOwhvABz1+fAiSC934PhgQAEP+XdPx6zRBLiq5Zzgt/gEQCNf/fcoEQIDAQAB"
}

# ZeptoMail's return-path host follows a provider-standard shape
# (bounce-zem.send) but the exact prefix is part of the issued record, so it
# is overridable. The CNAME target is what actually gates creation.
variable "zepto_bounce_host" {
  description = "ZeptoMail return-path CNAME host (bounce.<subdomain>) from the ZeptoMail dashboard."
  type        = string
  default     = "bounce-zem.send"
}

variable "zepto_bounce_cname" {
  description = "ZeptoMail return-path CNAME target from the ZeptoMail dashboard. Empty = record not created."
  type        = string
  default     = "cluster89.zeptomail.com."
}

# ---------------------------------------------------------------------------
# Legacy de-duke.com zone inputs.
#
# The de-duke.com REGISTRATION is locked to AWS, but its DNS records were
# migrated to Google Cloud DNS before the AWS account closed. The .com zone is
# live and authoritative and must keep resolving while (and after) registration
# recovery. These defaults are the EXACT values the .com records carried before
# the .org migration; they are pinned here so the legacy zone can never drift.
# Do not repoint them at the .org values.
# ---------------------------------------------------------------------------
variable "legacy_api_domain" {
  description = "Legacy de-duke.com API hostname (pinned so the .com record never drifts)."
  type        = string
  default     = "api.de-duke.com"
}

variable "legacy_cdn_domain" {
  description = "Legacy de-duke.com CDN hostname (pinned so the .com record never drifts)."
  type        = string
  default     = "cdn.de-duke.com"
}

variable "legacy_admin_fqdn" {
  description = "Legacy de-duke.com Admin Web Console hostname (Vercel CNAME)."
  type        = string
  default     = "admin.de-duke.com"
}

variable "legacy_marketing_fqdn" {
  description = "Legacy de-duke.com Marketing Site apex hostname (Vercel A record)."
  type        = string
  default     = "de-duke.com"
}

variable "legacy_marketing_www_fqdn" {
  description = "Legacy de-duke.com Marketing Site www hostname (Vercel CNAME)."
  type        = string
  default     = "www.de-duke.com"
}

# Vercel targets captured for the OLD .com projects. They stay pinned here so
# the .com records keep their exact targets; the .org records use the
# separately re-captured vercel_* variables.
variable "legacy_vercel_cname_target" {
  description = "Vercel CNAME target for the legacy admin.de-duke.com record."
  type        = string
  default     = "4e88bf4fa2333825.vercel-dns-017.com."
}

variable "legacy_vercel_marketing_cname_target" {
  description = "Vercel CNAME target for the legacy www.de-duke.com record."
  type        = string
  default     = "1c969cc0900a2edb.vercel-dns-017.com."
}

variable "legacy_vercel_apex_ips" {
  description = "Vercel A-record IP(s) for the legacy de-duke.com apex."
  type        = list(string)
  default     = ["216.198.79.1"]
}

# Exact pre-migration .com apex TXT set: SPF + Google site verification +
# Zoho domain verification. These tokens remain valid only for de-duke.com.
variable "legacy_root_txt_records" {
  description = "TXT records for the legacy de-duke.com apex (exact pre-migration values)."
  type        = list(string)
  default = [
    "\"v=spf1 include:zohomail.com include:zeptomail.net ~all\"",
    "\"google-site-verification=TDf3Xy_2XQitmbVtdlj41ZHG1orI26gvvyHPJXTtwvE\"",
    "\"zoho-verification=zb48910551.zmverify.zoho.com\"",
  ]
}

# Zoho Mail DKIM for de-duke.com -- 1024-bit key fits a single <=255-char TXT
# string, which Zoho's checker accepts.
variable "legacy_zoho_dkim_selector" {
  description = "Zoho DKIM selector for the legacy de-duke.com zone."
  type        = string
  default     = "zoho"
}

variable "legacy_zoho_dkim_txt" {
  description = "Zoho DKIM TXT value for de-duke.com (exact pre-migration value)."
  type        = string
  default     = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCQIN+Mrf0RjA5CpHN5pEed3zUHqwSW0t022X3W/mJWXqUTJuICKyzVmAWDUS1+PwIElJ8BHQ1IGnKoJmVcV1AK61tXiXGJEAbbQN7EfflwQxFQl8cBCbI/OeJEyT2E558qmBROYx1HPVJOLAouzXlOA0Ds8aBrYOH5E88PEqWfLwIDAQAB"
}

# ZeptoMail DKIM + return-path for de-duke.com -- exact pre-migration values.
variable "legacy_zepto_dkim_host" {
  description = "ZeptoMail DKIM host for the legacy de-duke.com zone."
  type        = string
  default     = "1110642._domainkey.send"
}

variable "legacy_zepto_dkim_txt" {
  description = "ZeptoMail DKIM TXT value for de-duke.com (exact pre-migration value)."
  type        = string
  default     = "k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCG1JLXCEF/8PmuFpMNw7lmN9kGBsB+Pqt//NU4R9xADHaoZFEWeWtE3b5WbLbp9yzQP2FQGFyhSScqbubH0+wsaCx/AhNJRdlpUs8Ucs4D6Lw4/TRzQFhaTdV2/6plTh9yxg/GGsDVM4vrXc2s2B4StGBXb+5eA4dp03jv2BzI2QIDAQAB"
}

variable "legacy_zepto_bounce_host" {
  description = "ZeptoMail return-path CNAME host for the legacy de-duke.com zone."
  type        = string
  default     = "bounce-zem.send"
}

variable "legacy_zepto_bounce_cname" {
  description = "ZeptoMail return-path CNAME target for the legacy de-duke.com zone."
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
