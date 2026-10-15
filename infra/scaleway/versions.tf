terraform {
  required_version = ">= 1.10.0" # use_lockfile on the s3 backend

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "2.86.0" # exact: 2.83.0 broke plan on Postgres state
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }
  }

  backend "s3" {
    bucket       = "dembrane-eu-tfstate"
    key          = "eu-prod/terraform.tfstate"
    region       = "fr-par"
    use_lockfile = true
    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}

provider "scaleway" {
  project_id = var.project_id
  region     = var.region
  zone       = var.zone
}

# Only used when var.dns_enabled is true. The token comes from CLOUDFLARE_DNS_TOKEN.
provider "cloudflare" {
  api_token = var.cloudflare_dns_token
}
