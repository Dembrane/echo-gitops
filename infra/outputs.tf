output "vpc_id" {
  value       = digitalocean_vpc.echo_vpc.id
  description = "VPC ID"
}

output "redis_private_uri" {
  value       = digitalocean_database_cluster.redis.private_uri
  description = "Redis connection URI"
  sensitive   = true
}

output "postgres_private_uri" {
  value       = digitalocean_database_cluster.postgres.private_uri
  description = "Postgres connection URI"
  sensitive   = true
}

output "postgres_pool_uri" {
  value       = digitalocean_database_connection_pool.postgres_pool.uri
  description = "Postgres connection URI"
  sensitive   = true
}

output "registry_url" {
  value       = local.env == "prod" ? null : digitalocean_container_registry.registry[0].endpoint
  description = "Container registry URL"
}

output "spaces_endpoint" {
  value       = digitalocean_spaces_bucket.uploads.endpoint
  description = "Spaces endpoint"
}

# spaces doesn't allow to create keys yet
# so create them manually
# https://github.com/digitalocean/terraform-provider-digitalocean/issues/880
# https://github.com/digitalocean/doctl/issues/936

// spaces output
// ams3.digitaloceanspaces.com
// bucket name (dev)  : dbr-echo-dev-uploads.ams3.digitaloceanspaces.com
// bucket name (prod) : dbr-echo-prod-uploads.ams3.digitaloceanspaces.com

output "vercel_dashboard_project_id" {
  value = local.env == "dev" ? vercel_project.dashboard[0].id : null
}

output "vercel_dashboard_staging_environment_id" {
  value = local.env == "dev" ? vercel_custom_environment.dashboard_env_staging[0].id : null
}

output "vercel_portal_project_id" {
  value = local.env == "dev" ? vercel_project.portal[0].id : null
}

output "vercel_portal_staging_environment_id" {
  value = local.env == "dev" ? vercel_custom_environment.portal_env_staging[0].id : null
}

# output "ingress_lb_ip" {
#   value = digitalocean_reserved_ip.echo_lb_ip.ip_address
# }
