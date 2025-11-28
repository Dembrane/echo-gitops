# Architecture

## Core Systems
- Terraform in `infra/` provisions the DigitalOcean VPC, Kubernetes cluster, managed Postgres, Redis, Spaces, and optional registry before seeding namespaces and registry credentials (infra/main.tf:80-195).
- Argo CD Applications (`echo-*`, `echo-monitoring-*`) track this repository’s `main` branch with automated prune/self-heal and namespace creation (argo/echo-dev.yaml:1-23, argo/echo-monitoring-prod.yaml:1-23).
- The `helm/echo` chart deploys the API server, worker tiers (worker, workerCpu, workerScheduler), Directus, and Neo4j along with shared env configuration and ingress/rollout settings (helm/echo/values.yaml:1-166).
- `helm/monitoring` delivers Prometheus, Grafana, Loki, promtail, node-exporter, blackbox checks, and alertmanager with storage and ingress defaults (helm/monitoring/values.yaml:1-112).
- Sealed secrets house sensitive config for each namespace, edited locally via `secret-manager.sh` before sealing (secret-manager.sh:104-189, secrets/sealed-backend-secrets-dev.yaml:1-18).
- `ai-infra` bootstraps a GCS-backed Terraform state bucket and Vertex AI endpoint plus service-account IAM for Gemini usage (ai-infra/state/main.tf:1-31, ai-infra/vertex/main.tf:1-20, ai-infra/README.md:5-30).

## External Surfaces
- Echo ingress publishes `directus` and `api` hostnames with Let’s Encrypt TLS through nginx (helm/echo/values.yaml:143-159).
- Monitoring ingress can expose Grafana/Prometheus endpoints with optional basic auth (helm/monitoring/values.yaml:1-60).
- GCP service-account credentials for AI workloads are stored as a SealedSecret consumed in the Argo CD namespace (ai-infra/k8s/sealed-argocd-gcp-sa-dev.yaml:1-15).

## Operational Tooling
- `secret-manager.sh` adds, updates, or compares plaintext secrets before they are sealed into manifests (secret-manager.sh:4-189).
- `scripts/query_logs.py` provides Loki queries with chunking/pagination options for deeper troubleshooting (scripts/LOKI_LOG_QUERY.md:5-132).
- `scripts/k6/sendChunks.js` simulates participant audio uploads for regression/load testing (scripts/k6/README.md:11-35).

## Environment Flow
1. Select the Terraform workspace (`default` for dev, `prod` for production) and apply to reconcile DigitalOcean resources (infra/main.tf:3-97).
2. Argo CD syncs `helm/echo` and `helm/monitoring` using the environment-specific value files tracked in this repo (argo/echo-prod.yaml:9-23, helm/echo/values-prod.yaml:1-166).
3. Secrets are rotated by editing plaintext manifests, sealing them, and applying via kubectl as documented in the infra comments (infra/main.tf:24-52, secrets/sealed-backend-secrets-prod.yaml:1-24).
4. When AI capabilities are needed, fetch the sealed GCP credentials, run the `ai-infra/state` bootstrap, then apply the `vertex` module to create endpoints and service accounts (ai-infra/README.md:5-30, ai-infra/vertex/main.tf:1-20).
