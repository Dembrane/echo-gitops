resource "google_project_service" "required" {
  for_each = toset([
    "storage.googleapis.com",
    "iam.googleapis.com",
    "aiplatform.googleapis.com",
  ])

  service                    = each.key
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_storage_bucket" "tf_state" {
  name          = var.bucket_name
  location      = var.location
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 3650
    }
  }
}


