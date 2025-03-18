# Only create Vercel resources for dev environment
# Skip these resources for production environment / because it is the same "vercel_project"

resource "vercel_project" "portal" {
  count = local.env == "prod" ? 0 : 1

  name                                 = "echo-portal"
  auto_assign_custom_domains           = false
  enable_affected_projects_deployments = false
  framework                            = "vite"
}

resource "vercel_custom_environment" "portal_env_staging" {
  count = local.env == "prod" ? 0 : 1

  project_id = vercel_project.portal[0].id
  name       = "staging"
}

resource "vercel_project" "dashboard" {
  count = local.env == "prod" ? 0 : 1

  name                                 = "echo-dashboard"
  auto_assign_custom_domains           = false
  enable_affected_projects_deployments = false
  framework                            = "vite"
}

resource "vercel_custom_environment" "dashboard_env_staging" {
  count = local.env == "prod" ? 0 : 1

  project_id = vercel_project.dashboard[0].id
  name       = "staging"
}

# you will manually need to add domains and environment variables to the project
