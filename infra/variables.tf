variable "do_region" {
  type    = string
  default = "ams3" # DigitalOcean region for all resources
}

variable "do_token" {
  description = "DigitalOcean API token for CSI driver"
  type        = string
  sensitive   = true
}

variable "spaces_access_key" {
  type        = string
  description = "DigitalOcean Spaces Access Key"
  sensitive   = true
}

variable "spaces_secret_key" {
  type        = string
  description = "DigitalOcean Spaces Secret Key"
  sensitive   = true
}

variable "vercel_api_token" {
  type        = string
  description = "Vercel API Token"
  sensitive   = true
}

