# Instructions:

# before running terraform apply, run:
# terraform workspace show 
# for dev: terraform workspace select default
# for prod: terraform workspace select -or-create prod 
# use different .tfvars if needed

# terraform workspace select default
# terraform plan -var-file=./terraform.tfvars
# terraform apply -var-file=./terraform.tfvars

# terraform workspace select prod
# terraform plan -var-file=./terraform-prod.tfvars
# terraform apply -var-file=./terraform-prod.tfvars

# TODO: automate this later

# doctl k8s c list
# doctl k8s c kubeconfig save dbr-echo-dev-k8s-cluster
# doctl k8s c kubeconfig save dbr-echo-prod-k8s-cluster


/**

secrets:

kubeseal --context=do-ams3-dbr-echo-dev-k8s-cluster \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets \
  < dev.yaml > echo-backend-secrets-dev.yaml

kubectl apply -f echo-backend-secrets-dev.yaml

kubeseal --context=do-ams3-dbr-echo-prod-k8s-cluster \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets \
  < prod.yaml > echo-backend-secrets-prod.yaml

kubectl apply -f echo-backend-secrets-prod.yaml

*/

# argo:

# kubectl apply -f echo-dev.yaml
# kubectl apply -f echo-prod.yaml

# kubectl port-forward svc/argocd-server -n argocd 8080:443
# username: admin
# password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# settings -> repositories -> add repository -> https://github.com/dembrane/echo-gitops.git 

# ingress: 

# ingress is already through do-loadbalancer therefore, grab the ip from the console and point your domain to it

# vercel:

# manually and add the environment variables

locals {
  # If workspace is default, use "dev" as the environment name
  # env: "dev" | "prod"
  env = terraform.workspace == "default" ? "dev" : "prod"
}

resource "digitalocean_vpc" "echo_vpc" {
  name     = "echo-${local.env}-vpc"
  region   = var.do_region
  ip_range = local.env == "prod" ? "10.10.10.0/24" : "10.10.11.0/24" # RFC1918 private IP ranges, /24 subnet
}

resource "digitalocean_kubernetes_cluster" "doks" {
  name     = "dbr-echo-${local.env}-k8s-cluster"
  region   = var.do_region
  vpc_uuid = digitalocean_vpc.echo_vpc.id
  version  = "1.32.2-do.0"
  node_pool {
    name       = "default-pool"
    size       = "s-4vcpu-8gb" # 4vCPU 8GB nodes
    auto_scale = true
    min_nodes  = local.env == "prod" ? 2 : 1 # prod : dev
    max_nodes  = local.env == "prod" ? 6 : 3 # prod : dev
    tags       = ["dbr-echo", local.env]
  }
}

# Managed Postgres for the environment
resource "digitalocean_database_cluster" "postgres" {
  name                 = "dbr-echo-${local.env}-postgres"
  private_network_uuid = digitalocean_vpc.echo_vpc.id
  engine               = "pg" # Postgres
  version              = "16" # e.g., Postgres version
  size                 = local.env == "prod" ? "db-s-2vcpu-4gb" : "db-s-1vcpu-1gb"
  region               = var.do_region
  node_count           = 1 # single node (for simplicity; prod could use HA with 2+ nodes)
  tags                 = ["dbr-echo", local.env, "postgres"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_database_connection_pool" "postgres_pool" {
  name       = "dbr-echo-${local.env}-postgres-pool"
  cluster_id = digitalocean_database_cluster.postgres.id
  db_name    = "defaultdb"
  size       = 10
  mode       = "transaction"

  user = digitalocean_database_cluster.postgres.user
}

resource "digitalocean_database_cluster" "redis" {
  name                 = "dbr-echo-${local.env}-redis"
  private_network_uuid = digitalocean_vpc.echo_vpc.id
  engine               = "redis"
  version              = "7" # Redis version
  size                 = local.env == "prod" ? "db-s-2vcpu-4gb" : "db-s-1vcpu-1gb"
  eviction_policy      = local.env == "prod" ? "volatile_lru" : "volatile_lru"
  region               = var.do_region
  node_count           = 1
  tags                 = ["dbr-echo", local.env, "redis"]
}

resource "digitalocean_spaces_bucket" "uploads" {
  name   = "dbr-echo-${local.env}-uploads"
  region = var.do_region

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_container_registry" "registry" {
  # already created in dev
  count = local.env == "prod" ? 0 : 1

  name                   = "dbr-cr"
  subscription_tier_slug = "basic"
  region                 = var.do_region
}

data "digitalocean_container_registry" "shared_registry" {
  name = "dbr-cr"
}

resource "digitalocean_container_registry_docker_credentials" "registry_credentials" {
  registry_name = local.env == "prod" ? data.digitalocean_container_registry.shared_registry.name : digitalocean_container_registry.registry[0].name
}

resource "time_sleep" "wait_for_kubernetes" {
  depends_on      = [digitalocean_kubernetes_cluster.doks]
  create_duration = "30s"
}

resource "kubernetes_namespace" "echo_ns" {
  metadata {
    name = "echo-${local.env}"
  }

  depends_on = [time_sleep.wait_for_kubernetes]
}

data "digitalocean_kubernetes_cluster" "doks_data" {
  name       = "dbr-echo-${local.env}-k8s-cluster" # Use the same name as your resource
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
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-name"
    value = "echo-${local.env}-ingress-lb"
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


resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.12.2" # Use the latest version or pin as needed
  namespace        = "kube-system"
  create_namespace = false # kube-system already exists

  depends_on = [time_sleep.wait_for_kubernetes]
}

# Create secret for DigitalOcean CSI driver
resource "kubernetes_secret" "do_csi_secret" {
  metadata {
    name      = "digitalocean"
    namespace = "kube-system"
  }

  data = {
    "access-token" = base64encode(var.do_token)
  }

  depends_on = [time_sleep.wait_for_kubernetes]
}

data "http" "do_csi_manifests" {
  for_each = {
    "crds"                = "https://raw.githubusercontent.com/digitalocean/csi-digitalocean/master/deploy/kubernetes/releases/csi-digitalocean-v4.13.0/crds.yaml"
    "driver"              = "https://raw.githubusercontent.com/digitalocean/csi-digitalocean/master/deploy/kubernetes/releases/csi-digitalocean-v4.13.0/driver.yaml"
    "snapshot-controller" = "https://raw.githubusercontent.com/digitalocean/csi-digitalocean/master/deploy/kubernetes/releases/csi-digitalocean-v4.13.0/snapshot-controller.yaml"
  }

  url = each.value
}

resource "kubectl_manifest" "do_csi_driver" {
  depends_on = [kubernetes_secret.do_csi_secret]

  for_each = {
    "crds"                = "https://raw.githubusercontent.com/digitalocean/csi-digitalocean/master/deploy/kubernetes/releases/csi-digitalocean-v4.13.0/crds.yaml"
    "driver"              = "https://raw.githubusercontent.com/digitalocean/csi-digitalocean/master/deploy/kubernetes/releases/csi-digitalocean-v4.13.0/driver.yaml"
    "snapshot-controller" = "https://raw.githubusercontent.com/digitalocean/csi-digitalocean/master/deploy/kubernetes/releases/csi-digitalocean-v4.13.0/snapshot-controller.yaml"
  }

  yaml_body = data.http.do_csi_manifests[each.key].response_body
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }

  depends_on = [time_sleep.wait_for_kubernetes]
}

