# Edge Services in front of the ingress load balancer: a web application firewall run by an EU
# provider, so the security layer adds no subprocessor outside the EU.
#
# Stages: hostnames -> TLS -> WAF -> load balancer. No cache stage: every response is per user,
# and cached responses would skip the WAF.
#
# Traffic reaches the edge only once the app hostnames are CNAMEs to the pipeline endpoint
# (output edge_endpoint). Until then this changes nothing for users. The managed certificate is
# issued after that DNS change, so the cutover is its own change.

resource "scaleway_edge_services_plan" "main" {
  # Starter: one pipeline, one backend, plus the WAF add-on, 5M inspected requests a month.
  name = "starter"
}

resource "scaleway_edge_services_pipeline" "main" {
  name        = "dembrane-eu-prod"
  description = "WAF in front of the ingress load balancer"
  depends_on  = [scaleway_edge_services_plan.main]
}

# The load balancer belongs to the ingress-nginx Service (cloud controller), so it is looked up
# through the reserved address it holds, and its frontend by port.
data "scaleway_lb_frontends" "ingress" {
  lb_id = local.ingress_lb_id
  zone  = var.zone
}

locals {
  ingress_lb_id          = "${var.zone}/${scaleway_lb_ip.ingress.lb_id}"
  ingress_https_frontend = one([for f in data.scaleway_lb_frontends.ingress.frontends : f.id if f.inbound_port == 443])
}

resource "scaleway_edge_services_backend_stage" "ingress" {
  pipeline_id = scaleway_edge_services_pipeline.main.id

  lb_backend_config {
    lb_config {
      id          = local.ingress_lb_id
      frontend_id = local.ingress_https_frontend
      zone        = var.zone
      # ingress-nginx terminates TLS with its own certificates. No domain_name: the edge passes
      # the request's Host on, so one backend serves every app hostname.
      is_ssl = true
      # Live updates are server-sent events. The edge drops websocket upgrades unless this is
      # on, so a later websocket use would otherwise fail only behind the edge.
      has_websocket = true
    }
  }
}

resource "scaleway_edge_services_waf_stage" "main" {
  pipeline_id      = scaleway_edge_services_pipeline.main.id
  backend_stage_id = scaleway_edge_services_backend_stage.ingress.id
  # log_only: matches are logged to Cockpit and still passed. Blocking waits until the logs show
  # which rules our own traffic trips (exclusion_rules by CRS id).
  mode           = var.edge_waf_mode
  paranoia_level = var.edge_waf_paranoia_level
}

resource "scaleway_edge_services_tls_stage" "main" {
  pipeline_id         = scaleway_edge_services_pipeline.main.id
  waf_stage_id        = scaleway_edge_services_waf_stage.main.id
  managed_certificate = true
}

resource "scaleway_edge_services_dns_stage" "main" {
  pipeline_id  = scaleway_edge_services_pipeline.main.id
  tls_stage_id = scaleway_edge_services_tls_stage.main.id
  fqdns        = [for h in var.edge_hosts : "${h}.${var.base_domain}"]
}

resource "scaleway_edge_services_head_stage" "main" {
  pipeline_id   = scaleway_edge_services_pipeline.main.id
  head_stage_id = scaleway_edge_services_dns_stage.main.id
}
