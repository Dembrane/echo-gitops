#!/usr/bin/env bash
# Creates the one bucket that holds Terraform state for scaleway/. Everything else is Terraform.
# Needs the scw CLI and SCW_ACCESS_KEY / SCW_SECRET_KEY in the environment. Safe to run twice.
set -euo pipefail

BUCKET="${STATE_BUCKET:-dembrane-eu-tfstate}"
export SCW_DEFAULT_PROJECT_ID="${SCW_DEFAULT_PROJECT_ID:-c581992c-8cce-4c75-acef-2b2a1cc0aea9}"
export SCW_DEFAULT_ORGANIZATION_ID="${SCW_DEFAULT_ORGANIZATION_ID:-$SCW_DEFAULT_PROJECT_ID}"
export SCW_DEFAULT_REGION=fr-par

if scw object bucket list 2>/dev/null | grep -q "^$BUCKET "; then
  echo "bucket $BUCKET exists"
else
  scw object bucket create "$BUCKET" enable-versioning=true acl=private tags.0=dembrane-eu-prod
fi
