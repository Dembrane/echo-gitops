variable "project_id" {
  type    = string
  default = "c581992c-8cce-4c75-acef-2b2a1cc0aea9"
}

variable "region" {
  # Amsterdam for everything that holds data; models and email exist only in Paris (fr-par).
  type    = string
  default = "nl-ams"
}

variable "zone" {
  type    = string
  default = "nl-ams-1"
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
  # amd64, because the images are built for amd64 only, the same images production runs.
  # The cheaper 8 GB types (BASIC2-A2C-8G) are arm64 and would need a second image build.
  description = "Kapsule node type: the cheapest amd64 8 GB type (fallback PLAY2-MICRO)."
  default     = "DEV1-L"
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

variable "app_key_generation" {
  type        = number
  description = "Bump to replace the app's API key."
  default     = 1
}
