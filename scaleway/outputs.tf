locals {
  # Name -> record. Names are relative to dembrane.com.
  dns_records = concat(
    [for h in ["dashboard", "portal", "api", "grafana"] : {
      key     = "a-${h}"
      name    = "${h}.${var.base_domain}"
      type    = "A"
      content = scaleway_lb_ip.ingress.ip_address
    }],
    [
      {
        key     = "spf"
        name    = var.base_domain
        type    = "TXT"
        content = scaleway_tem_domain.main.spf_config
      },
      {
        key     = "dkim"
        name    = trimsuffix(scaleway_tem_domain.main.dkim_name, ".")
        type    = "TXT"
        content = scaleway_tem_domain.main.dkim_config
      },
      {
        key      = "mx"
        name     = var.base_domain
        type     = "MX"
        content  = trimsuffix(scaleway_tem_domain.main.mx_config, ".")
        priority = 10
      },
      {
        key     = "dmarc"
        name    = trimsuffix(scaleway_tem_domain.main.dmarc_name, ".")
        type    = "TXT"
        content = scaleway_tem_domain.main.dmarc_config
      },
    ]
  )
}

output "dns_records" {
  description = "Records to create in the dembrane.com zone, DNS only (never proxied)."
  value       = local.dns_records
}

output "ingress_ip" {
  value = scaleway_lb_ip.ingress.ip_address
}

output "cluster_id" {
  value = scaleway_k8s_cluster.main.id
}

output "registry_endpoint" {
  value = scaleway_registry_namespace.main.endpoint
}

output "uploads_bucket" {
  value = scaleway_object_bucket.uploads.name
}

output "uploads_endpoint" {
  value = scaleway_object_bucket.uploads.api_endpoint
}
