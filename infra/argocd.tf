provider "helm" {
  kubernetes {
    host                   = digitalocean_kubernetes_cluster.doks.endpoint
    token                  = digitalocean_kubernetes_cluster.doks.kube_config[0].token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.doks.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = digitalocean_kubernetes_cluster.doks.endpoint
  token                  = digitalocean_kubernetes_cluster.doks.kube_config[0].token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.doks.kube_config[0].cluster_ca_certificate)
  load_config_file       = false
}

# Create a dedicated namespace for ArgoCD
resource "kubernetes_namespace" "argocd" {
  depends_on = [digitalocean_kubernetes_cluster.doks]

  metadata {
    name = "argocd"
  }
}

# Install ArgoCD using the Helm provider
resource "helm_release" "argocd" {
  depends_on = [kubernetes_namespace.argocd]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.8.8" # Specify your desired version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Basic configuration values
  set {
    name  = "server.service.type"
    value = "LoadBalancer" # Or ClusterIP if you plan to use an Ingress
  }

  # Optional: Set admin password 
  set_sensitive {
    name = "configs.secret.argocdServerAdminPassword"
    # This is the bcrypted hash of your password - generate using:
    # htpasswd -nbBC 10 "" yourpassword | tr -d ':\n' | sed 's/$2y/$2a/'
    value = "$2a$10$hI2iRa4C5AFgG/pAytvKz.e6rXgLUYjL4.GA8HyMIrUEGC/VSBjue"
  }

  # Additional configurations can be set here
  values = [
    <<-EOT
    server:
      extraArgs:
        - --insecure
      config:
        repositories: |
          - type: git
            url: https://github.com/dembrane/echo-gitops.git
        
    # Global settings
    global:
      image:
        repository: quay.io/argoproj/argocd
    EOT
  ]
}
