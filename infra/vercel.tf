# Only create Vercel resources for dev environment
# Skip for prod (same project) and testing (no frontend)

resource "vercel_project" "portal" {
  count = local.env == "dev" ? 1 : 0

  name                                 = "echo-portal"
  auto_assign_custom_domains           = true
  enable_affected_projects_deployments = false
  framework                            = "vite"

  vercel_authentication = {
    deployment_type = "none"
  }
}

resource "vercel_custom_environment" "portal_env_staging" {
  count = local.env == "dev" ? 1 : 0

  project_id = vercel_project.portal[0].id
  name       = "staging"
}

resource "vercel_project" "dashboard" {
  count = local.env == "dev" ? 1 : 0

  name                                 = "echo-dashboard"
  auto_assign_custom_domains           = true
  enable_affected_projects_deployments = false
  framework                            = "vite"

  vercel_authentication = {
    deployment_type = "none"
  }
}

resource "vercel_custom_environment" "dashboard_env_staging" {
  count = local.env == "dev" ? 1 : 0

  project_id = vercel_project.dashboard[0].id
  name       = "staging"
}

# you will manually need to add domains and environment variables to the project
