resource "digitalocean_kubernetes_cluster" "doks" {
  name    = "dbr-echo-${var.env}-k8s-cluster"
  region  = var.do_region
  version = "1.32.2-do.0"
  node_pool {
    name       = "default-pool"
    size       = "s-2vcpu-4gb" # 2vCPU 4GB nodes
    auto_scale = true
    min_nodes  = 1
    max_nodes  = var.env == "prod" ? 4 : 2 # max 2 nodes for dev, 4 for prod
    tags       = ["dbr-echo", var.env, "k8s"]
  }
}

# Managed Postgres for the environment
resource "digitalocean_database_cluster" "postgres" {
  name       = "dbr-echo-${var.env}-postgres"
  engine     = "pg" # Postgres
  version    = "16" # e.g., Postgres version
  size       = var.env == "prod" ? "db-s-2vcpu-4gb" : "db-s-1vcpu-1gb"
  region     = var.do_region
  node_count = 1 # single node (for simplicity; prod could use HA with 2+ nodes)
  tags       = ["dbr-echo", var.env, "postgres"]
}

# Create an application user with a strong random password
resource "digitalocean_database_user" "app_user" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "dembrane" # username
}

# Create a database in the cluster (optional, defaultdb exists by default)
resource "digitalocean_database_db" "app_db" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "dembrane" # name of the database
}

resource "digitalocean_database_cluster" "redis" {
  name       = "dbr-echo-${var.env}-redis"
  engine     = "redis"
  version    = "7" # Redis version
  size       = var.env == "prod" ? "db-s-2vcpu-4gb" : "db-s-1vcpu-1gb"
  region     = var.do_region
  node_count = 1
  tags       = ["dbr-echo", var.env, "redis"]
}

resource "digitalocean_spaces_bucket" "uploads" {
  name   = "dbr-echo-${var.env}-uploads"
  region = var.do_region
}

resource "digitalocean_container_registry" "registry" {
  name                   = "dbr-cr"
  subscription_tier_slug = "basic"
  region                 = var.do_region
}

resource "digitalocean_container_registry_docker_credentials" "registry_credentials" {
  registry_name = digitalocean_container_registry.registry.name
}

resource "time_sleep" "wait_for_kubernetes" {
  depends_on      = [digitalocean_kubernetes_cluster.doks]
  create_duration = "30s"
}

resource "kubernetes_namespace" "echo_ns" {
  metadata {
    name = "echo-${var.env}"
  }

  depends_on = [time_sleep.wait_for_kubernetes]
}

data "digitalocean_kubernetes_cluster" "doks_data" {
  name = "dbr-echo-${var.env}-k8s-cluster" # Use the same name as your resource
}

resource "kubernetes_secret" "registry_credentials" {
  depends_on = [time_sleep.wait_for_kubernetes]

  metadata {
    name      = "do-registry-secret"
    namespace = kubernetes_namespace.echo_ns.metadata[0].name
  }

  data = {
    ".dockerconfigjson" = digitalocean_container_registry_docker_credentials.registry_credentials.docker_credentials
  }

  type = "kubernetes.io/dockerconfigjson"
}

provider "kubernetes" {
  host  = data.digitalocean_kubernetes_cluster.doks_data.endpoint
  token = data.digitalocean_kubernetes_cluster.doks_data.kube_config[0].token
  cluster_ca_certificate = base64decode(
    data.digitalocean_kubernetes_cluster.doks_data.kube_config[0].cluster_ca_certificate
  )
}

provider "helm" {
  kubernetes {
    host                   = data.digitalocean_kubernetes_cluster.doks_data.endpoint
    token                  = data.digitalocean_kubernetes_cluster.doks_data.kube_config[0].token
    cluster_ca_certificate = base64decode(data.digitalocean_kubernetes_cluster.doks_data.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = data.digitalocean_kubernetes_cluster.doks_data.endpoint
  token                  = data.digitalocean_kubernetes_cluster.doks_data.kube_config[0].token
  cluster_ca_certificate = base64decode(data.digitalocean_kubernetes_cluster.doks_data.kube_config[0].cluster_ca_certificate)
  load_config_file       = false
}

### ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [time_sleep.wait_for_kubernetes]
}

# this doesnt work just do 
# kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# username: admin
# kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# kubectl apply -f echo-dev.yaml

# resource "helm_release" "argocd" {
#   depends_on = [kubernetes_namespace.argocd]

#   name       = "argocd"
#   repository = "https://argoproj.github.io/argo-helm"
#   chart      = "argo-cd"
#   version    = "5.51.4" # Specify your desired version
#   namespace  = kubernetes_namespace.argocd.metadata[0].name

#   # Basic configuration values
#   set {
#     name  = "server.service.type"
#     value = "LoadBalancer" # Or ClusterIP if you plan to use an Ingress
#   }

#   set {
#     name  = "server.service.port"
#     value = "80"
#   }

#   # Optional: Set admin password 
#   set_sensitive {
#     name = "configs.secret.argocdServerAdminPassword"
#     # This is the bcrypted hash of your password - generate using:
#     # htpasswd -nbBC 10 "" yourpassword | tr -d ':\n' | sed 's/$2y/$2a/'
#     value = "$2a$10$hI2iRa4C5AFgG/pAytvKz.e6rXgLUYjL4.GA8HyMIrUEGC/VSBjue"
#   }

#   # Additional configurations can be set here
#   values = [
#     <<-EOT
#     server:
#       extraArgs:
#         - --insecure
#     EOT
#   ]
# }
