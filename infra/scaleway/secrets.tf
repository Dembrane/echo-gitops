# Credentials and the kubeconfig go to files outside the repo, mode 600. They are also in the
# (private) state bucket, which is why that bucket stays private.

locals {
  secrets_dir = pathexpand(var.secrets_dir)
  db_host     = scaleway_rdb_instance.main.private_network[0].ip
  db_port     = scaleway_rdb_instance.main.private_network[0].port
  db_url      = "postgres://${scaleway_rdb_instance.main.user_name}:${random_password.db.result}@${local.db_host}:${local.db_port}/${scaleway_rdb_database.app.name}?sslmode=require"
}

resource "local_sensitive_file" "kubeconfig" {
  filename        = pathexpand(var.kubeconfig_path)
  content         = scaleway_k8s_cluster.main.kubeconfig[0].config_file
  file_permission = "0600"
}

resource "local_sensitive_file" "db" {
  filename        = "${local.secrets_dir}/database.env"
  file_permission = "0600"
  content         = <<-EOT
    DATABASE_URL=${local.db_url}
    POSTGRES_HOST=${local.db_host}
    POSTGRES_PORT=${local.db_port}
    POSTGRES_USER=${scaleway_rdb_instance.main.user_name}
    POSTGRES_PASSWORD=${random_password.db.result}
    POSTGRES_DB=${scaleway_rdb_database.app.name}
    POSTGRES_PUBLIC_HOST=${try(scaleway_rdb_instance.main.load_balancer[0].ip, "")}
    POSTGRES_PUBLIC_PORT=${try(scaleway_rdb_instance.main.load_balancer[0].port, "")}
    APP_DATABASE_URL=postgres://${scaleway_rdb_user.app.name}:${random_password.db_app.result}@${local.db_host}:${local.db_port}/${scaleway_rdb_database.app.name}?sslmode=require
    GRAFANA_DB_USER=${scaleway_rdb_user.grafana.name}
    GRAFANA_DB_PASSWORD=${random_password.db_grafana.result}
  EOT
}

resource "local_sensitive_file" "infra" {
  filename        = "${local.secrets_dir}/infra.env"
  file_permission = "0600"
  content         = <<-EOT
    INGRESS_IP=${scaleway_lb_ip.ingress.ip_address}
    CLUSTER_ID=${scaleway_k8s_cluster.main.id}
    REGISTRY_ENDPOINT=${scaleway_registry_namespace.main.endpoint}
    UPLOADS_BUCKET=${scaleway_object_bucket.uploads.name}
    UPLOADS_ENDPOINT=${scaleway_object_bucket.uploads.api_endpoint}
    SMTP_HOST=${scaleway_tem_domain.main.smtp_host}
    SMTP_PORT=${scaleway_tem_domain.main.smtps_port}
  EOT
}
