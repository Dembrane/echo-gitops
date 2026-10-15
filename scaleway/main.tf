locals {
  tags = [var.tag]
}

# ---- network ----------------------------------------------------------------

resource "scaleway_vpc" "main" {
  name = "dembrane-eu-prod"
  tags = local.tags
}

resource "scaleway_vpc_private_network" "main" {
  name   = "dembrane-eu-prod"
  vpc_id = scaleway_vpc.main.id
  tags   = local.tags
}

# ---- kubernetes -------------------------------------------------------------

resource "scaleway_k8s_cluster" "main" {
  name                        = "dembrane-eu-prod"
  type                        = "kapsule" # free shared control plane
  version                     = var.k8s_version
  cni                         = "cilium"
  private_network_id          = scaleway_vpc_private_network.main.id
  delete_additional_resources = true
  tags                        = local.tags

  auto_upgrade {
    enable                        = true
    maintenance_window_start_hour = 2
    maintenance_window_day        = "sunday"
  }
}

resource "scaleway_k8s_pool" "main" {
  cluster_id          = scaleway_k8s_cluster.main.id
  name                = "main"
  node_type           = var.node_type
  zone                = var.zone
  size                = var.pool_size
  min_size            = var.pool_size
  max_size            = var.pool_max_size
  autoscaling         = true
  autohealing         = true
  wait_for_pool_ready = true
  tags                = local.tags
}

# A fixed public address for the ingress load balancer. The ingress-nginx Service asks for it
# by address (scaleway/install.sh), so DNS survives the Service being recreated.
resource "scaleway_lb_ip" "ingress" {
  zone = var.zone
  tags = local.tags
}

# ---- postgres ---------------------------------------------------------------

resource "random_password" "db" {
  # Scaleway asks for a digit, an upper, a lower and a special character; "-" and "_" keep the
  # password safe inside a connection URL.
  length           = 40
  special          = true
  override_special = "-_"
  min_special      = 1
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}

resource "scaleway_rdb_instance" "main" {
  name              = "dembrane-eu-prod"
  engine            = "PostgreSQL-16"
  node_type         = var.db_node_type
  is_ha_cluster     = false # one client at a time; daily backups are the recovery path
  user_name         = "dembrane_admin"
  password          = random_password.db.result
  volume_type       = "sbs_5k"
  volume_size_in_gb = var.db_volume_gb
  disable_backup    = false
  tags              = local.tags

  private_network {
    pn_id       = scaleway_vpc_private_network.main.id
    enable_ipam = true
  }
}

resource "scaleway_rdb_database" "app" {
  instance_id = scaleway_rdb_instance.main.id
  name        = "dembrane"
}

# The public endpoint accepts nobody (documentation range). The app reaches the database over
# the private network, which the ACL does not apply to.
resource "scaleway_rdb_acl" "main" {
  instance_id = scaleway_rdb_instance.main.id
  acl_rules {
    ip          = "192.0.2.1/32"
    description = "placeholder: public access closed"
  }
}

# ---- object storage, registry ----------------------------------------------

resource "scaleway_object_bucket" "uploads" {
  name = "dembrane-eu-prod-uploads"
  tags = { env = var.tag }

  cors_rule {
    allowed_origins = var.cors_origins
    allowed_methods = ["GET", "PUT", "POST", "HEAD", "DELETE"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "scaleway_object_bucket_acl" "uploads" {
  bucket = scaleway_object_bucket.uploads.id
  acl    = "private"
}

resource "scaleway_registry_namespace" "main" {
  name      = "dembrane-eu-prod"
  is_public = false
}

# ---- transactional email ----------------------------------------------------

resource "scaleway_tem_domain" "main" {
  name       = var.base_domain
  accept_tos = true
}
