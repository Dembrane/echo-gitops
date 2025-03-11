output "vpc_id" {
  value       = digitalocean_vpc.echo_vpc.id
  description = "VPC ID"
}

output "redis_uri" {
  value       = digitalocean_database_cluster.redis.private_uri
  description = "Redis connection URI"
  sensitive   = true
}

output "postgres_uri" {
  value       = digitalocean_database_cluster.postgres.private_uri
  description = "Postgres connection URI"
  sensitive   = true
}

output "registry_url" {
  value       = digitalocean_container_registry.registry.endpoint
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
  value = vercel_project.dashboard.id
}

output "vercel_dashboard_staging_environment_id" {
  value = vercel_custom_environment.dashboard_env_staging.id
}

output "vercel_portal_project_id" {
  value = vercel_project.portal.id
}

output "vercel_portal_staging_environment_id" {
  value = vercel_custom_environment.portal_env_staging.id
}

output "ingress_lb_ip" {
  value = digitalocean_reserved_ip.echo_lb_ip.ip_address
}
