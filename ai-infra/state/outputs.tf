output "tf_state_bucket_name" {
  value       = google_storage_bucket.tf_state.name
  description = "Name of the created GCS bucket for Terraform state"
}


