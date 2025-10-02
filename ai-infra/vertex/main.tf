resource "google_vertex_ai_endpoint" "default" {
  name         = var.endpoint_display_name
  display_name = var.endpoint_display_name
  region       = var.region
  location     = var.location
  project      = var.project_id
}
