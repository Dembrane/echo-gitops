resource "vercel_project" "portal" {
  name                                 = "echo-portal"
  auto_assign_custom_domains           = false
  enable_affected_projects_deployments = false
  framework                            = "vite"
}

resource "vercel_custom_environment" "portal_env_staging" {
  project_id = vercel_project.portal.id
  name       = "staging"
}

resource "vercel_project" "dashboard" {
  name                                 = "echo-dashboard"
  auto_assign_custom_domains           = false
  enable_affected_projects_deployments = false
  framework                            = "vite"
}

resource "vercel_custom_environment" "dashboard_env_staging" {
  project_id = vercel_project.dashboard.id
  name       = "staging"
}

# you will manually need to add domains and environment variables to the project
