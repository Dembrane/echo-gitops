# scaleway/

Terraform for the EU production instance on Scaleway (project `eu-dembrane-web-prod`, fr-par):
VPC and private network, a Kapsule cluster (Cilium, one autoscaling pool), managed PostgreSQL 16
(HA, backups on, private network), a private uploads bucket with CORS, a private container
registry, a Transactional Email domain, a reserved IP for the ingress load balancer, and the
Cloudflare records for `*.eu.dembrane.com`.

## State

State lives in the Object Storage bucket `dembrane-eu-tfstate` (versioned, private, `use_lockfile`).
Create that one bucket first; everything else is Terraform:

```sh
export SCW_ACCESS_KEY=... SCW_SECRET_KEY=...
./scaleway/bootstrap-state.sh
```

## Run

```sh
export SCW_ACCESS_KEY=... SCW_SECRET_KEY=...
export AWS_ACCESS_KEY_ID=$SCW_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$SCW_SECRET_KEY   # s3 backend
cd scaleway && terraform init && terraform plan -out=tfplan
```

DNS is off unless `TF_VAR_dns_enabled=true`, with `TF_VAR_cloudflare_dns_token` and
`TF_VAR_cloudflare_zone_id` set. Only names under `eu.dembrane.com` are managed, all DNS only.
`terraform output dns_records` lists them whether or not they are created.

Credentials (database URL and password, addresses) and the kubeconfig are written outside the
repo, mode 600: `~/.config/dembrane-eu/` and `~/.kube/eu-prod.yaml`.

The provider is pinned exactly (2.83.0 broke plan on Postgres state); read release notes before
bumping it.

## Cluster add-ons

`scaleway/addons/install.sh` installs ingress-nginx, cert-manager, sealed-secrets and Argo CD at
the versions the DigitalOcean production cluster runs. It uses `~/.kube/eu-prod.yaml` only.
