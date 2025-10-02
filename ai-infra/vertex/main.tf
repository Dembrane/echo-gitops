resource "google_vertex_ai_endpoint" "default" {
  name         = var.endpoint_display_name
  display_name = var.endpoint_display_name
  region       = var.region
  location     = var.location
  project      = var.project_id
}

# Service account to invoke publisher models on Vertex (gemini)
resource "google_service_account" "vertex_caller" {
  account_id   = var.vertex_sa_account_id
  display_name = var.vertex_sa_display_name
  project      = var.project_id
}

# Minimal role to invoke publisher models
resource "google_project_iam_member" "vertex_caller_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.vertex_caller.email}"
}
