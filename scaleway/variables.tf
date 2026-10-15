variable "project_id" {
  type    = string
  default = "c581992c-8cce-4c75-acef-2b2a1cc0aea9"
}

variable "region" {
  type    = string
  default = "fr-par"
}

variable "zone" {
  type    = string
  default = "fr-par-1"
}

variable "tag" {
  type    = string
  default = "dembrane-eu-prod"
}

variable "k8s_version" {
  type    = string
  default = "1.36"
}

variable "node_type" {
  type        = string
  description = "Kapsule node type: the cheapest 8 GB type Kapsule accepts (fallbacks DEV1-L, PLAY2-MICRO)."
  default     = "BASIC2-A2C-8G"
}

variable "pool_size" {
  type    = number
  default = 1
}

variable "pool_max_size" {
  type    = number
  default = 2
}

variable "db_node_type" {
  type    = string
  default = "db-play2-nano"
}

variable "db_volume_gb" {
  type    = number
  default = 10
}

variable "base_domain" {
  type    = string
  default = "eu.dembrane.com"
}

variable "cors_origins" {
  type = list(string)
  default = [
    "https://dashboard.eu.dembrane.com",
    "https://portal.eu.dembrane.com",
  ]
}

variable "secrets_dir" {
  type        = string
  description = "Where credentials are written, mode 600. Never inside a repo."
  default     = "~/.config/dembrane-eu"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/eu-prod.yaml"
}

variable "dns_enabled" {
  type        = bool
  description = "Create the Cloudflare records. Off until CLOUDFLARE_DNS_TOKEN exists."
  default     = false
}

variable "cloudflare_dns_token" {
  type      = string
  sensitive = true
  default   = null
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Zone id of dembrane.com. Needed when dns_enabled is true."
  default     = null
}
