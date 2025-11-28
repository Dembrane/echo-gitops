# AGENTS.md

## 1) Snapshot
- Project: Dembrane ECHO GitOps • Repo type: mono (Terraform + Helm + Argo CD GitOps) (README.md:40, infra/main.tf:80)
- Entrypoints: Terraform stacks (`infra/`, `ai-infra/`), Argo CD apps (`echo-*`, `echo-monitoring-*`), Helm charts (`helm/echo`, `helm/monitoring`) (infra/main.tf:80-195, ai-infra/README.md:16-24, argo/echo-dev.yaml:1-23, helm/monitoring/Chart.yaml:1-6)
- License & governance: Business Source License 1.1 with GPLv3 transition; no CODEOWNERS/CONTRIBUTING tracked (LICENSE:1-25)
- Quickstart (≤3 commands)
  1) `cd infra && terraform init -backend-config="bucket=<tf-state>" -backend-config="prefix=infra"` (README.md:107-120)
  2) `terraform apply -var-file=terraform.tfvars` (infra/main.tf:9-15)
  3) `kubectl apply -f argo/echo-dev.yaml && kubectl apply -f argo/echo-monitoring-dev.yaml` (README.md:142-149)

## 2) Tech & Tooling
- Runtimes & package managers: Terraform ≥1.0, kubectl, Helm 3, kubeseal, doctl per prerequisites; Python 3 + `requests` for Loki tooling (README.md:84-103, scripts/LOKI_LOG_QUERY.md:5-17).
- Core libraries by role: DigitalOcean Terraform resources provision VPC/K8s/DB/cache/object storage (infra/main.tf:80-145); Argo CD Applications drive GitOps sync (argo/echo-dev.yaml:1-23); `helm/echo` manages API, Directus, worker tiers, and Neo4j (helm/echo/values.yaml:42-166); `helm/monitoring` delivers Prometheus/Grafana/Loki stack (helm/monitoring/values.yaml:1-61); `ai-infra` provisions Vertex AI endpoints and IAM (ai-infra/vertex/main.tf:1-20).
- Scripts you’ll actually use: `secret-manager.sh` for base64 edits, batch updates, and compares (secret-manager.sh:4-193); `scripts/query_logs.py` wraps Loki queries with chunking/pagination (scripts/LOKI_LOG_QUERY.md:29-132); `scripts/k6/sendChunks.js` replays participant uploads via k6 (scripts/k6/README.md:11-35).
- Code style (lint/format/type): Terraform providers are version-locked by `.terraform.lock.hcl`; run CLI formatters (`terraform fmt`, `helm lint`) locally as needed (infra/.terraform.lock.hcl:1-33).

## 3) Architecture (mental model)
- Modules/services & responsibilities: Terraform builds DigitalOcean infra then seeds namespaces/secrets; Helm deploys application workloads (API, workers, Directus, Neo4j) and monitoring stack (infra/main.tf:80-195, helm/echo/values.yaml:42-166, helm/monitoring/values.yaml:1-112).
- Data & external surfaces: Postgres, Redis, and Spaces are managed services; ingress exposes `directus`/`api` hostnames with TLS and monitoring endpoints with optional auth (infra/main.tf:101-145, helm/echo/values.yaml:143-159, helm/monitoring/values.yaml:1-60).
- Notable patterns: Argo CD auto-prune/self-heal enforces drift control; HPAs and priority classes tune scaling for core workloads (argo/echo-dev.yaml:18-23, helm/echo/templates/hpa-api-server.yaml:1-32, helm/echo/templates/priorityclass-echo-critical.yaml:1-11).
- Diagram → see `.agents/architecture.md`.

## 4) Build / Run / Test
- Setup: Select the Terraform workspace, provide tfvars, export Spaces credentials, and follow kubeseal instructions before apply (infra/main.tf:3-52, README.md:107-133).
- Dev workflow: Update image tags and config in `helm/echo/values.yaml`, commit to `main`, and let Argo auto-sync dev/prod apps (helm/echo/values.yaml:1-40, argo/echo-dev.yaml:9-23).
- Test workflow (coverage): Use `scripts/k6/sendChunks.js` for load validation and `scripts/query_logs.py` for log triage; both require manual invocation (scripts/k6/README.md:11-35, scripts/LOKI_LOG_QUERY.md:29-132).
- CI gates: GitOps enforcement happens via Argo CD automated sync/prune; no separate CI workflows tracked in repo (argo/echo-monitoring-prod.yaml:18-23).

## 5) Conventions & Non-Obvious Rules
- Layout & naming: Repo split across `argo/`, `helm/`, `infra/`, `scripts/`, `secrets/`, and `ai-infra/` per README map (README.md:72-78).
- Commits & branches: All Argo apps follow `targetRevision: main`; protect that branch before enabling auto-sync in production (argo/echo-prod.yaml:9-10, NEED_HELP.md:17).
- Hooks & codegen: Secrets are edited via `secret-manager.sh`, which injects plaintext comments before base64 encoding—respect the workflow to avoid malformed manifests (secret-manager.sh:104-156).
- Gotchas: Managed Postgres/Spaces resources set `prevent_destroy`, so plan carefully before destructive changes; resealing secrets requires kubeseal access to each cluster (infra/main.tf:112-145, infra/main.tf:34-52).

## 6) Security / Ops
- Secrets & env strategy: Maintain plaintext manifests locally, update with `secret-manager.sh`, seal with `kubeseal`, and apply per env (infra/main.tf:24-52, secret-manager.sh:4-189).
- Access control: Terraform issues namespaces and registry secrets tied to cluster credentials; Vertex service accounts are scoped via IAM bindings (infra/main.tf:170-195, ai-infra/vertex/main.tf:9-20).
- Observability/logging: Monitoring chart exposes Prometheus/Grafana/Loki with storage and ingress defaults; use the Loki helper script for precise queries (helm/monitoring/values.yaml:1-112, scripts/LOKI_LOG_QUERY.md:29-132).
- Perf & a11y: HPAs cap CPU/memory utilization and priority classes reserve capacity for critical pods—review before tuning resources (helm/echo/templates/hpa-api-server.yaml:1-32, helm/echo/templates/priorityclass-echo-critical.yaml:1-11).

## 7) History Timeline
- 2025-03-06: Initial repo scaffold and base configs (3a426a9)
- 2025-03-07: Terraform refactor aligning Argo + Kubernetes wiring (012f020)
- 2025-05-09: Added worker scheduler deployment for background jobs (434b671)
- 2025-05-15: Introduced LiteLLM sizing across deployments (c7a6eab)
- 2025-05-23: Merged Runpod/Whisper config updates for non-prod (3e6a86b)
- 2025-09-04: Landed monitoring production stack via Helm (214933d)
- 2025-09-04: Fixed Argo prod app to track `main` (2afbe72)
- 2025-09-09: Resolved Neo4j crash loops with probes/priority tweaks (e0b2b8a)
- 2025-10-08: Consolidated dev scaling adjustments for HPAs (6205791)
- 2025-10-13: Tuned prod scaling through dedicated merge (dccd907)
- 2025-10-13: Promoted backend image `v1.11.1` to prod (9164b35)

## 8) Known Gaps / TODOs
- Terraform automation: Workspace selection and apply steps remain manual → infra/main.tf:3
- Infra backlog: Azure LLMs + Runpod service provisioning TBD → NEED_HELP.md:4-6
- Secrets workflow: Move more secret management into Terraform/stateful tooling → NEED_HELP.md:6
- Frontend ops: Replace Vercel-managed front-end secrets with unified flow → NEED_HELP.md:7
- Helm polish: Add worker probes and optimize resource profiles → NEED_HELP.md:10-11
- Monitoring: Build richer dashboards and alerting coverage → NEED_HELP.md:13-15
- Governance: Enforce protection on `main` branch → NEED_HELP.md:17
- Logging: Strip `%2Cerror%2C` noise from Directus logs → NEED_HELP.md:19

## 9) Agent Recipes
- Task: Apply dev infrastructure
  - Context: Terraform in `infra/` manages DigitalOcean resources; dev uses the `default` workspace (infra/main.tf:3-97).
  - Steps:
    1. **UNRUN (safety)** `cd infra && terraform workspace select default`
    2. **UNRUN (safety)** `terraform init -backend-config="bucket=<tf-state>" -backend-config="prefix=infra"`
    3. **UNRUN (safety)** `terraform apply -var-file=terraform.tfvars`
  - Acceptance: Terraform apply finishes without pending changes and `kubernetes_namespace.echo-dev` reports up-to-date (infra/main.tf:170-175).
- Task: Promote backend release to prod
  - Context: Argo watches the Helm chart and image tags in `values-prod.yaml` (helm/echo/values-prod.yaml:1-82, argo/echo-prod.yaml:9-23).
  - Steps:
    1. Update `global.imageTag` and any config overrides in `helm/echo/values-prod.yaml`.
    2. Commit to `main` with meaningful message and push.
    3. Confirm Argo sync + rollout status for `echo-prod`.
  - Acceptance: Argo shows `Sync: Synced` and pods run the new image tag without degraded HPAs.
- Task: Rotate a backend secret
  - Context: Secrets are stored as SealedSecrets; plaintext editing happens via the helper script (secret-manager.sh:4-189, secrets/sealed-backend-secrets-dev.yaml:1-24).
  - Steps:
    1. Edit `secrets/backend-secrets-dev.yaml` via `./secret-manager.sh dev update`.
    2. **UNRUN (safety)** `kubeseal ... < secrets/backend-secrets-dev.yaml > secrets/sealed-backend-secrets-dev.yaml` (infra/main.tf:34-39).
    3. **UNRUN (safety)** `kubectl apply -f secrets/sealed-backend-secrets-dev.yaml`.
  - Acceptance: Argo reports healthy secrets sync and application pods consume the rotated value.
- Task: Tune worker CPU scaling
  - Context: Worker CPU deployment and HPA values live in the Helm chart (helm/echo/values.yaml:96-111, helm/echo/templates/hpa-worker-cpu.yaml:1-24).
  - Steps:
    1. Adjust `workerCpu` resources or replica limits in `helm/echo/values.yaml`.
    2. Update HPA thresholds if required in `helm/echo/templates/hpa-worker-cpu.yaml`.
    3. Commit and push; monitor Argo sync plus pod behavior.
  - Acceptance: Workers scale to the new limits without hitting throttling or OOM events.
- Task: Enable monitoring basic auth
  - Context: Monitoring ingress has toggles for basic auth (helm/monitoring/values.yaml:1-59).
  - Steps:
    1. Set `ingress.basicAuth.enabled: true` and provide credentials in `helm/monitoring/values-prod.yaml`.
    2. Commit changes and ensure Argo sync completes.
    3. Verify ingress prompts for auth before exposing dashboards.
  - Acceptance: Monitoring hosts require credentials and Grafana login works as expected.
- Task: Investigate recent errors via Loki
  - Context: Python helper script queries Loki with optional filters (scripts/LOKI_LOG_QUERY.md:29-132).
  - Steps:
    1. **UNRUN (safety)** `kubectl port-forward svc/loki 3100:3100 -n monitoring`.
    2. **UNRUN (safety)** `./scripts/query_logs.py --component api --hours 6 --text-contains "ERROR"`.
    3. Export to CSV if escalation is needed.
  - Acceptance: Relevant log slices retrieved; findings shared or ticketed.
- Task: Reproduce participant upload flow
  - Context: k6 script sends WebM chunks against API endpoints (scripts/k6/README.md:11-35, scripts/k6/sendChunks.js:1-93).
  - Steps:
    1. Place chunk files in `scripts/k6/audioChunks/`.
    2. **UNRUN (safety)** `(cd scripts/k6 && k6 run sendChunks.js -e PROJECT_ID=<id> -e START=0 -e END=5)`.
    3. Review API metrics and logs post-run.
  - Acceptance: Conversation lifecycle completes without errors; metrics show expected load.
- Task: Bootstrap Vertex AI endpoint
  - Context: `ai-infra/` includes state bucket + endpoint modules; GCP creds pulled from Argo (ai-infra/README.md:5-30, ai-infra/vertex/main.tf:1-20).
  - Steps:
    1. Fetch and export the GCP SA json from Argo via kube secret (ai-infra/README.md:5-12).
    2. **UNRUN (safety)** `cd ai-infra/state && terraform init && terraform apply -auto-approve`.
    3. **UNRUN (safety)** `cd ../vertex && terraform init ... && terraform apply -auto-approve`.
  - Acceptance: Vertex endpoint exists and service account bound to `roles/aiplatform.user`.
- Task: Add alert on worker timeouts
  - Context: Monitoring chart houses alertmanager config; NEED_HELP notes highlight worker timeouts (helm/monitoring/templates/alertmanager.yaml:1-120, NEED_HELP.md:21-25).
  - Steps:
    1. Add a new alert rule in `helm/monitoring/templates/alertmanager.yaml` targeting worker timeout metrics/logs.
    2. Provide Slack route details in `values-prod.yaml` if needed.
    3. Commit and push; confirm Argo sync and alert delivery.
  - Acceptance: Alert rule visible in Alertmanager and fires when timeout condition reproduces.

## 10) Evidence Ledger
- [E1] README.md:40 — Describes the GitOps purpose of this repository.
- [E2] infra/main.tf:80 — Terraform provisions the DigitalOcean VPC and Kubernetes cluster.
- [E3] helm/echo/values.yaml:42 — Echo workloads include Directus, API server, and worker tiers.
- [E4] helm/monitoring/values.yaml:1 — Monitoring stack covers Prometheus, Grafana, Loki, and storage.
- [E5] secret-manager.sh:4 — Secret management script handles list/update/batch/compare actions.
- [E6] scripts/LOKI_LOG_QUERY.md:5 — Loki helper depends on Python 3 and `requests`.
- [E7] scripts/k6/README.md:11 — k6 script documents the chunk upload workflow.
- [E8] ai-infra/README.md:5 — Vertex AI quickstart outlines credential fetch and Terraform apply.
- [E9] argo/echo-dev.yaml:18 — Argo CD auto-syncs with prune/self-heal enabled.
- [E10] NEED_HELP.md:4 — Outstanding infra/helm/monitoring tasks are tracked here.
- [E11] infra/.terraform.lock.hcl:1 — Provider lock file enforces Terraform version pinning.

## 11) Self-Healing Policy (manual invoke)
Refresh when:
- Fingerprint drift occurs (tracked path added/removed/changed) or adapters list changes.
- Topology changes: new/removed apps, services, workspaces, or major runtime shifts.
- Workflow/infra documentation changes (CI, Terraform, Helm, Argo, secrets) or policy docs update.
- TTL: 30 days since `generated_at_utc`.

Behavior:
- On refresh, recompute fingerprint, churn, architecture, deployment map, todos, and recipes in place.
- Preserve everything below the human-notes line verbatim.
- Keep edits scoped to `AGENTS.md` and `.agents/**`; never touch product code.

--- AUTO-GENERATED CONTENT ENDS ---
(Human Notes below persist across refreshes. Use this zone for institutional knowledge and decisions.)

## 12) Metadata
<!--
AGENTS-METADATA
generator: Repo-Intelligence@v4
generated_at_utc: 2025-10-28T13:36:18Z
repo_head_sha: 5d3dead
detectors: [argocd, helm, k6, sealed-secrets, terraform, python-script]
signature_ref: .agents/fingerprint.json
ttl_days: 30
-->

## 13) Contributor Guidance: Interactive Knowledge Capture (Manual)
When you run the agent, capture novel architecture/workflow changes not reflected here. Batch up to five items, then ask: “Found new context; add a brief evidence-backed note?” Choices: [Append] [Revise] [Skip] [Ignore this item]. On approval, save `.agents/inbox/<slug>.md` and optional `.agents/patches/` diff; never apply patches without explicit consent.
