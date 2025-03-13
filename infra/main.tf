resource "digitalocean_vpc" "echo_vpc" {
  name     = "echo-${var.env}-vpc"
  region   = var.do_region
  ip_range = var.env == "prod" ? "10.10.10.0/24" : "10.10.11.0/24" # RFC1918 private IP ranges, /24 subnet
}

resource "digitalocean_reserved_ip" "echo_lb_ip" {
  region = var.do_region
}

resource "digitalocean_kubernetes_cluster" "doks" {
  name     = "dbr-echo-${var.env}-k8s-cluster"
  region   = var.do_region
  vpc_uuid = digitalocean_vpc.echo_vpc.id
  version  = "1.32.2-do.0"
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
  name                 = "dbr-echo-${var.env}-postgres"
  private_network_uuid = digitalocean_vpc.echo_vpc.id
  engine               = "pg" # Postgres
  version              = "16" # e.g., Postgres version
  size                 = var.env == "prod" ? "db-s-2vcpu-4gb" : "db-s-1vcpu-1gb"
  region               = var.do_region
  node_count           = 1 # single node (for simplicity; prod could use HA with 2+ nodes)
  tags                 = ["dbr-echo", var.env, "postgres"]
}

resource "digitalocean_database_cluster" "redis" {
  name                 = "dbr-echo-${var.env}-redis"
  private_network_uuid = digitalocean_vpc.echo_vpc.id
  engine               = "redis"
  version              = "7" # Redis version
  size                 = var.env == "prod" ? "db-s-2vcpu-4gb" : "db-s-1vcpu-1gb"
  region               = var.do_region
  node_count           = 1
  tags                 = ["dbr-echo", var.env, "redis"]
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
  name       = "dbr-echo-${var.env}-k8s-cluster" # Use the same name as your resource
  depends_on = [time_sleep.wait_for_kubernetes]
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

# TODO: automate this later

# doctl k8s c list
# doctl k8s c kubeconfig save dbr-echo-dev-k8s-cluster

# secrets:
# - kubectl apply -n kube-system -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.20.2/controller.yaml
# kubectl apply -f echo-dev-secrets.yaml

# argo:
# - kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# kubectl apply -f echo-dev.yaml
# kubectl port-forward svc/argocd-server -n argocd 8080:443
# username: admin
# password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# settings -> repositories -> add repository -> https://github.com/dembrane/echo-gitops.git 

resource "helm_release" "sealed_secrets" {
  name             = "sealed-secrets"
  repository       = "https://bitnami-labs.github.io/sealed-secrets"
  chart            = "sealed-secrets"
  version          = "2.17.1"
  namespace        = "kube-system"
  create_namespace = true
}


resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.8.9"
  namespace        = "argocd"
  create_namespace = true
}

# Update the ingress-nginx configuration to explicitly set the loadBalancerIP
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.7.1"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.loadBalancerIP" # Explicitly set the loadBalancerIP
    value = digitalocean_reserved_ip.echo_lb_ip.ip_address
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-name"
    value = "echo-${var.env}-ingress-lb"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-size-unit"
    value = "1" # Smallest size
  }

  # Use the reserved IP for the ingress controller
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-floating-ip"
    value = "true"
  }

  # Assign the reserved IP to the load balancer
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-floating-ip-assignment"
    value = digitalocean_reserved_ip.echo_lb_ip.ip_address
  }

  # Important: Use TLS passthrough instead of DO certificate
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-tls-passthrough"
    value = "true"
  }

  depends_on = [time_sleep.wait_for_kubernetes]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.13.1"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [time_sleep.wait_for_kubernetes]
}
