terraform {

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = "~> 2.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }

  backend "s3" {
    endpoint                    = "https://ams3.digitaloceanspaces.com"
    bucket                      = "dbr-echo-tf-state-storage"
    key                         = "terraform.tfstate"
    region                      = "us-east-1" # Use any region (required but not actually used by Spaces)
    skip_credentials_validation = true        # Required for non-AWS S3 (DigitalOcean)
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}

provider "digitalocean" {
  token             = var.do_token          # DO API token
  spaces_access_id  = var.spaces_access_key # DO Spaces Access Key
  spaces_secret_key = var.spaces_secret_key # DO Spaces Secret Key
}

provider "vercel" {
  # Or omit this for the api_token to be read
  # from the VERCEL_API_TOKEN environment variable
  api_token = var.vercel_api_token

  # Optional default team for all resources
  team = "dembrane"
}
