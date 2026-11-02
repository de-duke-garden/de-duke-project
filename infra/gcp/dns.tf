# De-Duke GCP Infrastructure -- Cloud DNS for de-duke.org.
# This is a GREENFIELD zone: there is no legacy zone to mirror. Every record
# below is either domain-agnostic (MX, SPF, DMARC) or supplied by an external
# provider dashboard (Zoho Mail, ZeptoMail, Google Search Console) via the
# variables in variables.tf.
#
# NOTE: renaming the managed zone (`de-duke-com` -> `de-duke-org`) is a
# destroy/create of the GCP zone, not an in-place update. That is expected and
# safe because GCP Cloud DNS was never authoritative for de-duke.com (the old
# domain is on AWS/Route53 and is no longer under our control), so no live
# resolution depends on this zone. Confirm with the operator that Cloud DNS
# has NOT been made authoritative for the apex before applying -- once the
# registrar's nameservers point at this zone, a destroy would drop resolution.

# The de-duke.org public zone. Safe to create while the registrar still points
# elsewhere; it only becomes authoritative when the registrar nameservers are
# switched to the name servers this zone reports (output dns_nameservers).
resource "google_dns_managed_zone" "deduke" {
  name        = "de-duke-org"
  dns_name    = "${var.domain_name}."
  project     = var.gcp_project_id
  description = "De-Duke public DNS for de-duke.org (Google Cloud DNS)"
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

# Apex TXT -- SPF only by default (Zoho mailboxes + Zepto transactional).
# Verification tokens (Google Search Console, Zoho domain verification) are
# domain-specific and are supplied per environment via root_txt_records; they
# are not committed here.
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

# Zoho Mail DKIM -- TXT record at <selector>._domainkey.<domain>.
# 1024-bit value fits a single TXT string. The count guard creates the record
# only once the domain-specific value is supplied from the Zoho dashboard;
# with count = 0 Terraform does not evaluate the name/rrdatas expressions, so
# an empty value can never produce a malformed record name.
resource "google_dns_record_set" "zoho_dkim" {
  count = var.zoho_dkim_txt != "" ? 1 : 0

  name         = "${var.zoho_dkim_selector}._domainkey.${var.domain_name}."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = ["\"${var.zoho_dkim_txt}\""]
}

# ZeptoMail DKIM -- TXT at <selector>._domainkey.send.de-duke.org.
# Both host and value are issued per domain (ZeptoMail dashboard), so this is
# count-guarded on both: no record is created while either is empty.
resource "google_dns_record_set" "zepto_dkim" {
  count = var.zepto_dkim_txt != "" && var.zepto_dkim_host != "" ? 1 : 0

  name         = "${var.zepto_dkim_host}.${var.domain_name}."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = ["\"${var.zepto_dkim_txt}\""]
}

# ZeptoMail return-path CNAME -- bounce.<send-subdomain>.de-duke.org.
# Count-guarded on both host and target; the bounce host prefix is part of the
# provider-issued record, so it must be confirmed in the ZeptoMail dashboard.
resource "google_dns_record_set" "zepto_bounce" {
  count = var.zepto_bounce_cname != "" && var.zepto_bounce_host != "" ? 1 : 0

  name         = "${var.zepto_bounce_host}.${var.domain_name}."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [var.zepto_bounce_cname]
}
