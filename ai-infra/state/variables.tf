variable "project_id" {
  type        = string
  description = "GCP project ID that owns the state bucket"
}

variable "region" {
  type        = string
  description = "Default region for provider operations"
  default     = "europe-west4"
}

variable "bucket_name" {
  type        = string
  description = "Name of the GCS bucket to store Terraform state"
}

variable "location" {
  type        = string
  description = "Location/region for the state bucket (e.g., US, EU, us-central1)"
  default     = "europe-west4"
}


