variable "project_id" {
  type        = string
  description = "GCP project ID for Vertex AI resources"
}

variable "region" {
  type        = string
  description = "Region for Vertex AI resources (e.g., us-central1)"
  default     = "europe-west4"
}

variable "endpoint_display_name" {
  type        = string
  description = "Display name for the Vertex AI endpoint"
  default     = "echo-ai-endpoint"
}

variable "location" {
  type        = string
  description = "Location/region for the Vertex AI endpoint"
  default     = "europe-west4"
}

# Service account for calling publisher models (Gemini)
variable "vertex_sa_account_id" {
  type        = string
  description = "Service account account_id (name) for Vertex caller"
  default     = "vertex-caller"
}

variable "vertex_sa_display_name" {
  type        = string
  description = "Display name for the Vertex caller service account"
  default     = "Vertex caller"
}
