# De-Duke GCP Infrastructure -- Cloud DNS (dual-zone model).
#
# Two managed zones coexist here:
#
#   de-duke-com  (resource "google_dns_managed_zone" "deduke")
#       The LIVE, authoritative zone for the legacy de-duke.com domain. Its DNS
#       records were migrated to Google Cloud DNS before the AWS account was
#       closed. The de-duke.com *registration* is locked to AWS, but this zone
#       is what actually answers queries today, and it is managed by THIS
#       Terraform state. It must never be destroyed, so .com keeps resolving
#       while (and after) registration recovery is in progress. Every .com
#       record is pinned to the legacy_* variables so its values cannot drift.
#
#   de-duke-org  (resource "google_dns_managed_zone" "deduke_org")
#       The NEW primary zone for de-duke.org. It only becomes authoritative
#       once the de-duke.org registrar (Google Cloud Domains) nameservers point
#       at the name servers this zone reports (output dns_nameservers).

# ---------------------------------------------------------------------------
# de-duke.com -- live legacy zone. NEVER destroy.
# ---------------------------------------------------------------------------
# This zone answers production traffic for de-duke.com today. The registration
# is locked to AWS pending recovery, but the DNS zone itself lives on Google
# Cloud DNS. `prevent_destroy` is a hard guard: destroying (or address-renaming)
# this resource would take the old domain's site, API, CDN, and mail offline.
resource "google_dns_managed_zone" "deduke" {
  name        = "de-duke-com"
  dns_name    = "de-duke.com."
  project     = var.gcp_project_id
  description = "De-Duke public DNS for de-duke.com (live legacy zone; registration locked to AWS)"
  labels      = local.labels

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [terraform_data.api_propagation]
}

# ---------------------------------------------------------------------------
# de-duke.org -- new primary zone. Must stay stable.
# ---------------------------------------------------------------------------
# Creating this zone is safe while the registrar still points elsewhere; it
# only becomes authoritative when the registrar nameservers are switched to the
# values reported by output dns_nameservers.
resource "google_dns_managed_zone" "deduke_org" {
  name        = "de-duke-org"
  dns_name    = "de-duke.org."
  project     = var.gcp_project_id
  description = "De-Duke public DNS for de-duke.org (new primary domain, Google Cloud DNS)"
  labels      = local.labels

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [terraform_data.api_propagation]
}

# ===========================================================================
# de-duke.com records (legacy, live). These resource addresses and their
# inputs are pinned to their pre-migration values via the legacy_* variables.
# ===========================================================================

# api.de-duke.com -> LB IP.
resource "google_dns_record_set" "api" {
  count = var.legacy_api_domain != "" ? 1 : 0

  name         = "${var.legacy_api_domain}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [google_compute_global_address.lb.address]
}

# cdn.de-duke.com -> LB IP.
resource "google_dns_record_set" "cdn" {
  count = var.legacy_cdn_domain != "" ? 1 : 0

  name         = "${var.legacy_cdn_domain}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [google_compute_global_address.lb.address]
}

# admin.de-duke.com -> Vercel CNAME (Admin Web Console, DNS-only).
resource "google_dns_record_set" "admin" {
  count = var.legacy_admin_fqdn != "" && var.legacy_vercel_cname_target != "" ? 1 : 0

  name         = "${var.legacy_admin_fqdn}."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [var.legacy_vercel_cname_target]
}

# de-duke.com apex -> Vercel A record (Marketing Site; CNAME invalid at apex).
resource "google_dns_record_set" "marketing" {
  count = var.legacy_marketing_fqdn != "" ? 1 : 0

  name         = "${var.legacy_marketing_fqdn}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = var.legacy_vercel_apex_ips
}

# www.de-duke.com -> Vercel CNAME (Marketing Site primary host).
resource "google_dns_record_set" "marketing_www" {
  count = var.legacy_marketing_www_fqdn != "" && var.legacy_vercel_marketing_cname_target != "" ? 1 : 0

  name         = "${var.legacy_marketing_www_fqdn}."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [var.legacy_vercel_marketing_cname_target]
}

# MX -- Zoho Mail (shared with .org; the MX hosts are provider-generic).
resource "google_dns_record_set" "mx" {
  name         = "de-duke.com."
  type         = "MX"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = var.mx_records
}

# Apex TXT -- SPF + Google site verification + Zoho domain verification.
# Pinned to the exact pre-migration .com values so mail and verification keep
# working during the transition.
resource "google_dns_record_set" "root_txt" {
  name         = "de-duke.com."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = var.legacy_root_txt_records
}

# _dmarc.de-duke.com (policy is identical across both domains; shared var).
resource "google_dns_record_set" "dmarc_txt" {
  name         = "_dmarc.de-duke.com."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [var.dmarc_txt]
}

# Zoho Mail DKIM -- TXT at <selector>._domainkey.de-duke.com.
# The legacy value is a single <=255-char string, so it stays one TXT record.
# No `count`: this record has always existed unconditionally, and adding a count
# would change its state address and force a destroy/create.
resource "google_dns_record_set" "zoho_dkim" {
  name         = "${var.legacy_zoho_dkim_selector}._domainkey.de-duke.com."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = ["\"${var.legacy_zoho_dkim_txt}\""]
}

# ZeptoMail DKIM -- TXT at <selector>._domainkey.send.de-duke.com.
# No `count` (see zoho_dkim) -- the address must stay indexless.
resource "google_dns_record_set" "zepto_dkim" {
  name         = "${var.legacy_zepto_dkim_host}.de-duke.com."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = ["\"${var.legacy_zepto_dkim_txt}\""]
}

# ZeptoMail return-path CNAME -- bounce.<send-subdomain>.de-duke.com.
# No `count` (see zoho_dkim) -- the address must stay indexless.
resource "google_dns_record_set" "zepto_bounce" {
  name         = "${var.legacy_zepto_bounce_host}.de-duke.com."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke.name
  project      = var.gcp_project_id
  rrdatas      = [var.legacy_zepto_bounce_cname]
}

# ===========================================================================
# de-duke.org records (new primary). Provider-issued values (DKIM, bounce,
# verification tokens) stay count-guarded and blank by default: the .com keys
# must never be published under .org.
# ===========================================================================

# api.<domain> -> LB IP (created once api_domain is supplied / cutover-ready).
resource "google_dns_record_set" "api_org" {
  count = local.api_fqdn != "" ? 1 : 0

  name         = "${local.api_fqdn}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = [google_compute_global_address.lb.address]
}

# cdn.<domain> -> LB IP (created once cdn_domain is supplied / cutover-ready).
resource "google_dns_record_set" "cdn_org" {
  count = local.cdn_fqdn != "" ? 1 : 0

  name         = "${local.cdn_fqdn}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = [google_compute_global_address.lb.address]
}

# admin.<domain> -> Vercel CNAME (Admin Web Console, DNS-only).
resource "google_dns_record_set" "admin_org" {
  count = local.admin_fqdn != "" && var.vercel_cname_target != "" ? 1 : 0

  name         = "${local.admin_fqdn}."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = [var.vercel_cname_target]
}

# <domain> apex -> Vercel A record (Marketing Site; CNAME invalid at apex).
resource "google_dns_record_set" "marketing_org" {
  count = local.mkt_fqdn != "" ? 1 : 0

  name         = "${local.mkt_fqdn}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = var.vercel_apex_ips
}

# www.<domain> -> Vercel CNAME (Marketing Site primary host).
resource "google_dns_record_set" "marketing_www_org" {
  count = local.mkt_www_fqdn != "" && var.vercel_marketing_cname_target != "" ? 1 : 0

  name         = "${local.mkt_www_fqdn}."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = [var.vercel_marketing_cname_target]
}

# MX -- Zoho Mail for de-duke.org.
resource "google_dns_record_set" "mx_org" {
  name         = "${var.domain_name}."
  type         = "MX"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = var.mx_records
}

# Apex TXT -- SPF only by default (Zoho mailboxes + Zepto transactional).
# New .org verification tokens (Google Search Console, Zoho) are supplied per
# environment via root_txt_records; the .com tokens live in legacy_root_txt_records.
resource "google_dns_record_set" "root_txt_org" {
  name         = "${var.domain_name}."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = var.root_txt_records
}

# _dmarc.
resource "google_dns_record_set" "dmarc_txt_org" {
  name         = "_dmarc.${var.domain_name}."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = [var.dmarc_txt]
}

# Zoho Mail DKIM -- TXT at <selector>._domainkey.<domain>.
# Count-guarded: created only once the .org value is supplied from the Zoho
# dashboard. With count = 0 Terraform does not evaluate the name/rrdatas
# expressions, so an empty value can never produce a malformed record.
resource "google_dns_record_set" "zoho_dkim_org" {
  count = var.zoho_dkim_txt != "" ? 1 : 0

  name         = "${var.zoho_dkim_selector}._domainkey.${var.domain_name}."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = ["\"${var.zoho_dkim_txt}\""]
}

# ZeptoMail DKIM -- TXT at <selector>._domainkey.de-duke.org.
# Both host and value are issued per domain (ZeptoMail dashboard), so this is
# count-guarded on both: no record is created while either is empty.
resource "google_dns_record_set" "zepto_dkim_org" {
  count = var.zepto_dkim_txt != "" && var.zepto_dkim_host != "" ? 1 : 0

  name         = "${var.zepto_dkim_host}.${var.domain_name}."
  type         = "TXT"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  # ZeptoMail issues a 2048-bit DKIM key (~400 chars), which exceeds DNS's
  # 255-byte limit for a single character-string. Split it into 255-char
  # chunks and emit them as multiple quoted strings inside one TXT record;
  # resolvers reassemble the value.
  rrdatas = [
    join(" ", [
      for i in range(ceil(length(var.zepto_dkim_txt) / 255)) :
      "\"${substr(var.zepto_dkim_txt, i * 255, 255)}\""
    ])
  ]
}

# ZeptoMail return-path CNAME -- bounce.<send-subdomain>.de-duke.org.
# Count-guarded on both host and target; the bounce host prefix is part of the
# provider-issued record, so it must be confirmed in the ZeptoMail dashboard.
resource "google_dns_record_set" "zepto_bounce_org" {
  count = var.zepto_bounce_cname != "" && var.zepto_bounce_host != "" ? 1 : 0

  name         = "${var.zepto_bounce_host}.${var.domain_name}."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.deduke_org.name
  project      = var.gcp_project_id
  rrdatas      = [var.zepto_bounce_cname]
}
