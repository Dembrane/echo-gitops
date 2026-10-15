# Cloudflare records for dembrane.com. Off until dns_enabled = true and a token exists
# (CLOUDFLARE_DNS_TOKEN -> TF_VAR_cloudflare_dns_token, TF_VAR_cloudflare_zone_id).
# DNS only: proxied is always false, so no traffic passes through Cloudflare.

resource "cloudflare_dns_record" "eu" {
  for_each = var.dns_enabled ? { for r in local.dns_records : r.key => r } : {}

  zone_id  = var.cloudflare_zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  priority = try(each.value.priority, null)
  ttl      = 300
  proxied  = false
}
