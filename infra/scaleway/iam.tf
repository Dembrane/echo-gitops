# The key the app runs with, kept apart from the operator key: it reads and writes objects,
# calls the models, sends email and pulls images in this project, and can change no
# infrastructure.
# Rotation: bump `app_key_generation` and apply; the plan replaces the key.

resource "scaleway_iam_application" "app" {
  name        = "dembrane-eu-app"
  description = "Runtime key of the EU app: objects, models, email"
  tags        = local.tags
}

resource "scaleway_iam_policy" "app" {
  name           = "dembrane-eu-app"
  application_id = scaleway_iam_application.app.id
  rule {
    project_ids = [var.project_id]
    permission_set_names = [
      "ObjectStorageBucketsRead",
      "ObjectStorageObjectsRead",
      "ObjectStorageObjectsWrite",
      "ObjectStorageObjectsDelete",
      "GenerativeApisModelAccess",
      "TransactionalEmailEmailApiCreate",
      "ContainerRegistryReadOnly",
    ]
  }
}

resource "scaleway_iam_api_key" "app" {
  lifecycle {
    replace_triggered_by = [terraform_data.app_key_generation]
    # The organization caps key lifetime at one year and sets the expiry itself; rotate by
    # bumping the generation before it passes.
    ignore_changes = [expires_at]
  }
  application_id     = scaleway_iam_application.app.id
  description        = "dembrane-eu-app generation ${var.app_key_generation}"
  default_project_id = var.project_id
}

resource "terraform_data" "app_key_generation" {
  input = var.app_key_generation
}

resource "local_sensitive_file" "app" {
  filename        = "${local.secrets_dir}/app.env"
  file_permission = "0600"
  content         = <<-EOT
    SCW_APP_ACCESS_KEY=${scaleway_iam_api_key.app.access_key}
    SCW_APP_SECRET_KEY=${scaleway_iam_api_key.app.secret_key}
  EOT
}
