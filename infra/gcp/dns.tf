# De-Duke GCP Infrastructure -- Cloud DNS (replaces Route53 subdomain records).
# The de-duke.com public zone is created HERE, mirroring the AWS dns module's
# records. The zone is harmless until the registrar nameservers are repointed
# at cutover (README migration step 5) -- creating it now means zero DNS work
# at cutover beyond the registrar change.

# The public zone. The registrar currently points de-duke.com at Route53;
# this zone only becomes authoritative when nameservers are switched.
resource "google_dns_managed_zone" "deduke" {
  name        = "de-duke-com"
  dns_name    = "${var.domain_name}."
  project     = var.gcp_project_id
  description = "De-Duke public DNS (replaces Route53 zone records)"
  labels      = local.labels

  depends_on = [terraform_data.api_propagation]
}

# api.<domain> -> LB IP (created once api_domain is supplied / cutover-ready).
resource "google_dns_record_set" "api" {
  count = local.api_fqdn != "" ? 1 : 0

  name         = "${local.api_fqdn}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [google_compute_global_address.lb.address]
}

# cdn.<domain> -> LB IP (created once cdn_domain is supplied / cutover-ready).
resource "google_dns_record_set" "cdn" {
  count = local.cdn_fqdn != "" ? 1 : 0

  name         = "${local.cdn_fqdn}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [google_compute_global_address.lb.address]
}

# admin.<domain> -> Vercel CNAME (Admin Web Console, DNS-only).
resource "google_dns_record_set" "admin" {
  count = local.admin_fqdn != "" && var.vercel_cname_target != "" ? 1 : 0

  name         = "${local.admin_fqdn}."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [var.vercel_cname_target]
}

# <domain> apex -> Vercel A record (Marketing Site; CNAME invalid at apex).
resource "google_dns_record_set" "marketing" {
  count = local.mkt_fqdn != "" ? 1 : 0

  name         = "${local.mkt_fqdn}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = var.vercel_apex_ips
}

# www.<domain> -> Vercel CNAME (Marketing Site primary host).
resource "google_dns_record_set" "marketing_www" {
  count = local.mkt_www_fqdn != "" && var.vercel_marketing_cname_target != "" ? 1 : 0

  name         = "${local.mkt_www_fqdn}."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [var.vercel_marketing_cname_target]
}

# ---------------------------------------------------------------------------
# Email + verification records. Zoho Mail hosts the info/hello/legal@
# mailboxes; the transactional provider (Zepto/Resend) will add its SPF
# include + DKIM once chosen. SES/WorkMail records were removed with the
# AWS decommission.
# ---------------------------------------------------------------------------

# MX -- Zoho Mail.
resource "google_dns_record_set" "mx" {
  name         = "${var.domain_name}."
  type         = "MX"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = var.mx_records
}

# Apex TXT (Zoho SPF + Google site verification + Zoho domain verification).
resource "google_dns_record_set" "root_txt" {
  name         = "${var.domain_name}."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = var.root_txt_records
}

# _dmarc.
resource "google_dns_record_set" "dmarc_txt" {
  name         = "_dmarc.${var.domain_name}."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [var.dmarc_txt]
}
