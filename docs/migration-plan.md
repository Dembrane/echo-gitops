# Migration plan (2026-05-15)

Decision to move off DigitalOcean Kubernetes onto GCP Cloud Run, and to rewrite the Python backend to Node + Hono + Drizzle. The agent service (`agent/`) stays Python. Captured in the same conversation that produced [`triage-2026-05-14.md`](triage-2026-05-14.md); the triage was the trigger.

## TL;DR

```
Today                                  Target
─────                                  ──────
3× DOKS clusters (prod/dev/testing)    Cloud Run services (one per workload)
ArgoCD + Helm + Sealed Secrets         Terraform + Secret Manager
Self-hosted Prom/Grafana/Loki          Cloud Monitoring + Cloud Logging
DO Postgres / Redis / Spaces           Cloud SQL / Memorystore / GCS
Python (FastAPI, Dramatiq, APScheduler, Node + Hono + Drizzle + Cloud Tasks +
  in-process scheduler, nest_asyncio,    Cloud Scheduler. Agent service stays
  agentic_runtime lease system)          Python on Cloud Run.
Directus = data layer (HTTP REST hop)  Drizzle owns Postgres; Directus = admin UI
Neo4j (40Gi StatefulSet)               Dropped
Vercel frontends                       Cloud Run (or Firebase Hosting)
DO Container Registry                  Artifact Registry
This repo (echo-gitops)                Deleted
```

50k GCP credits cover an estimated 3-5 years at current DO spend (~$800-900/mo).

## Why now

Three forces lined up:

1. **The drift bug found on 2026-05-14.** ArgoCD `Application` CRs diverged silently from the git repo because nothing reconciles them after initial `kubectl apply`. 8 months of monitoring changes never deployed. This is a permanent shape of the current setup, not a one-off.
2. **The architecture has accumulated three concurrency systems** (Dramatiq + APScheduler + the hand-rolled Redis-lease agentic runtime in `agentic_runtime.py`), plus a `nest_asyncio.apply()` at module load and parallel sync/async Directus clients. Each was locally rational; together they are a tax on every change.
3. **Workload shape doesn't match Kubernetes.** Live measurement (2026-05-14): `echo-api` 6 replicas at ~25m CPU each, `echo-directus` at ~85m, `echo-neo4j` at 9m and idle, `echo-worker` bursty. Stateless containers with one stateful exception. This is Cloud Run's exact shape, and serverless containers scale-to-zero on non-prod, which K8s does not.

## Decisions

### 1. Move from DO Kubernetes to GCP Cloud Run

**Why:** workload shape fits, 50k credits, removes the entire `echo-gitops` repo plus Helm + ArgoCD + Sealed Secrets + cert-manager + ingress-nginx + self-hosted observability. Removes the drift bug class.

**How to apply:** any infra work from now on targets GCP, not DO. Don't invest in fixes that are specific to the K8s setup unless they ship pending value (see "What to do during runway" below).

### 2. Rewrite Python backend to Node + Hono + Drizzle

**Why:** the three-concurrency-systems problem is downstream of Python's sync/async split. AGENTS.md in the app repo confirms: *"No asyncio in Dramatiq actors — recurring event-loop corruption bugs led to this."* `tasks.py` is 1,704 lines; `scheduler.py` is 58 lines of `BlockingScheduler` with `MemoryJobStore` that holds schedule in process memory. None of this code is doing anything Python-specific (no NumPy, no Pandas, no PyTorch, no domain ML). The frontend is already TypeScript, so one language across the stack means shared types, shared Zod schemas, shared utilities.

**How to apply:** strangler pattern. Hono service on Cloud Run runs alongside Python FastAPI. Routes move one at a time. Same Postgres, same Redis. Both stacks alive in parallel until the last Python route migrates.

### 3. Keep `agent/` in Python

**Why:** the only real risk in the Python → Node port is LangGraph.js feature parity. The agent service already talks to the backend over HTTP (`echo_client.py`), so the language boundary equals the network boundary. Keeping it Python costs nothing in coupling and removes the only verification gate.

**How to apply:** `agent/` ships as its own Cloud Run service with its own Dockerfile, same as today.

### 4. Drizzle owns Postgres; Directus becomes admin-only

**Why:** the data layer is the half of the inversion that isn't done yet. The frontend already stopped using `@directus/sdk` and the backend already owns authz via `policies.py` (268 lines). The remaining smell is that every backend read/write goes `Node → Directus REST → Postgres` instead of `Node → Postgres`. Owning the schema via Drizzle migrations also deletes the `scripts/create_schema.py` pattern, which is an imperative workaround for not owning the schema.

**How to apply:** after workspaces ships, run `drizzle-kit introspect` against prod Postgres to capture schema as of that point. From then on Drizzle owns migrations. Existing tables stay Directus-managed and accessed via the legacy FastAPI until the corresponding Hono route ports over. Strangler at the table level.

### 5. Drop Neo4j

**Why:** 9m CPU, 2.7Gi memory, single replica, 40Gi PVC, not load-bearing. The one workload that doesn't fit Cloud Run is also the one that doesn't pull its weight.

**How to apply:** delete `deployment-neo4j.yaml`, `pvc-neo4j.yaml`, `service-neo4j.yaml` in the app repo's Helm chart when migration begins. Code call sites that import Neo4j get stubbed or removed.

### 6. Don't adopt app-of-apps

**Why:** this repo is being deleted in 2-3 months. Investing in better GitOps discipline for it is sunk cost. The 2026-05-14 drift bug gets fixed by manually applying the two pending Application YAMLs; future drift during the migration window is acceptable because the only Application changes that matter are the monitoring ones that just landed.

**How to apply:** if a contributor proposes app-of-apps adoption, point them at this doc.

## Day 0 progress (2026-05-15)

A "ship the pending monitoring fix" task surfaced additional cruft, most of which got cleaned up the same day. Captured here so future-me knows what's been done.

### Shipped to prod and dev

- Monitoring stack live on dev for the first time (Grafana, Prometheus, Loki, Alertmanager, blackbox-exporter, kube-state-metrics, node-exporter, promtail)
- Prod monitoring caught up to `main` (the 8-month drift bug from `triage-2026-05-14.md` is closed; PRs #22 / #23 / #24 finally deployed)
- Helm/Python `{{ }}` brace collision in `cronjob-warning-digest.yaml` fixed (was silently blocking the chart from rendering for weeks)
- Loki queries in the Health dashboard now respect the `$namespace` variable (was hardcoded to `echo-prod`)
- "Prod Health" dashboard renamed to "Health"; the namespace value is now injected per-env via `.Values.dashboards.namespace` in `helm/monitoring/values.yaml` (echo-dev) and `values-prod.yaml` (echo-prod), so the dashboard works correctly on either cluster
- "Pods stuck" table added to the Health dashboard for ImagePullBackOff / CrashLoopBackOff / ErrImagePull visibility (the 29-day broken echo-agent in the triage doc would have been spotted here)
- `prometheus.io/scrape` annotations removed from all 5 echo workloads (no `/metrics` endpoint exists; scrapes were producing ~17k 404s/day per api pod)
- 83 dead Prometheus pods reaped from prod
- All `argo/*.yaml` Application files standardized to `targetRevision: main`

### Cleaned up (dead infrastructure / orphan code)

- `helm/monitoring/SETUP_AUTH.md` and `secrets/sealed-monitoring-auth-secret-dev.yaml` deleted: basic-auth was scaffolded but never enabled (`ingress.basicAuth.enabled: false` in both values files)
- `echo-application-dashboard.json` deleted: queried app-emitted metrics that don't exist (Decision 1 confirms they never will)
- `echo-comprehensive-dashboard.json` deleted: wasn't even in `deployment-grafana.yaml`'s items list, so Grafana never loaded it
- Empty `echo-dev` namespace on prod cluster deleted (created 422d ago by manual `kubectl apply`, sat empty since)
- Obsolete `# NOTE: Loki queries are hardcoded` comment removed from `configmap-grafana-dashboards.yaml` (the hardcoding it warned about is what we fixed)

### Confirmed for follow-up

- **Neo4j workload is fully unused**: zero app imports across `server/`, `agent/`, `frontend/`; no `NEO4J_*` env injection anywhere. Helm chart deploys it unconditionally for no purpose. Strengthens Decision 5: safe to delete independently of any other migration phase, after a one-off `neo4j-admin database dump` for safety.
- **`prod-overview.json`** still has a hardcoded `"query": "echo-prod"` namespace dropdown (same pattern Health had pre-fix). Worth either parameterizing the same way or retiring if no one uses it.
- **`blackbox-exporter` Deployment on prod** (270d old) is not GitOps-managed: an ad-hoc `kubectl apply` from somewhere. Needs deliberate handling in Phase 2 (capture its config, recreate on Cloud Run, or accept that uptime probes move to Cloud Monitoring's synthetic checks).
- **Worker memory pattern is suspicious**: workers showed steady climb (16→20 GiB over 3h) before our rolling restart dropped them to ~4 GiB. Either legitimate queue depth growth OR an aiohttp session leak (consistent with the triage's "Unclosed client session" log pattern). Watch over the next 24h to decide. If leak, Decision 2 (Node rewrite) resolves it without further investment in Python fixes.

## Phasing

### Phase 0: runway, no disturbance to running stack

**Window:** today → workspaces epic ships (estimated 2-3 weeks)

Workspaces is mostly done and ships on the current Python + Directus stack. Migration must not interfere. Parallel work that touches **nothing** in the running system:

- GCP project + IAM + Terraform skeleton
- Cloud SQL Postgres provisioned (empty)
- Memorystore Redis (empty), GCS bucket, Artifact Registry, Secret Manager, VPC connector
- One "hello world" Hono service on Cloud Run pointed at the empty Cloud SQL, to validate the stack and shake out env/IAM/networking surprises
- DNS TTL audit on `dashboard.dembrane.com`, `portal.dembrane.com`, etc. — lower to 300s so cutover later is fast
- Apply the two pending monitoring Application YAMLs (P0 #1 and #2 in `triage-2026-05-14.md`) so workspaces ships with working alerts

### Phase 1: strangler begins

**Window:** workspaces ships → +4 weeks

- `drizzle-kit introspect` against prod Postgres captures schema baseline
- Hono service grows endpoints route-by-route, deployed to Cloud Run, fronted by a path-based router or weighted traffic split
- Each ported route migrates its tables from "FastAPI reads via Directus REST" to "Hono reads via Drizzle direct"
- Workers convert from Dramatiq actors to Cloud Tasks handlers, one queue at a time
- `scheduler.py` cron entries become Cloud Scheduler entries that POST to Hono endpoints; `scheduler.py` deleted

### Phase 2: port the rest, decommission

**Window:** +4 weeks → +8 weeks

- Remaining Python routes ported, FastAPI app retired
- Frontend deploys move from Vercel to Cloud Run (or Firebase Hosting for static)
- Data migration: `pg_dump | pg_restore` DO Postgres → Cloud SQL during a planned window; `rclone sync` Spaces → GCS
- DNS swing (TTLs already at 300s)
- DO clusters destroyed, DO managed services destroyed
- This repo (`echo-gitops`) archived

### Phase 3: cleanup

- Delete Helm charts in the app repo
- Delete `directus.py`, `directus_async.py`, `scheduler.py`, `tasks.py`, Dramatiq deps
- Delete Sealed Secrets workflow, replace with Secret Manager workflow
- Document the new architecture in `~/Documents/dembrane/echo/echo/AGENTS.md`

## What we keep, what we delete

### Keep

- App code logic (Docker images are portable in concept, Hono handlers port from FastAPI routes)
- `ai-infra/` Terraform — already GCP
- `agent/` Python service (LangGraph)
- AssemblyAI, Gemini, Sentry, PostHog integrations (all have Node SDKs)
- Postgres data, Redis usage patterns, S3 object layout

### Delete

- This repo: `argo/`, `helm/echo/`, `helm/monitoring/`, Sealed Secrets, the secrets pipeline
- App repo: `server/dembrane/tasks.py`, `scheduler.py`, `directus.py`, `directus_async.py`, `nest_asyncio` usage, `async_helpers.py`, `gunicorn_worker.py`, `asyncio_uvicorn_worker.py`, both worker startup shell scripts
- DO Container Registry, DO Postgres, DO Redis, DO Spaces, DO clusters
- Vercel deploys (frontends move to Cloud Run / Firebase Hosting)
- `@directus/sdk` from frontend (already done)
- `@mantine/charts` from frontend (already documented as forbidden in `AGENTS.md`)
- Neo4j

## Forking question on Directus admin UI

The current plan assumes Directus continues running as an admin UI for non-developer data ops. If no one actually uses it that way (only developers ever log in), Directus gets dropped entirely in Phase 2. Decide before Phase 1 starts; the choice affects how clean the schema can be (Directus expects certain metadata tables and field naming).

## Cost sketch

Current DO: ~$800-900/month, ~$10k/year.

Estimated GCP post-migration at current scale, no credits:
- Cloud Run (5 services, mixed always-on/scale-to-zero): ~$150-300
- Cloud SQL (db-custom-2-8192 equivalent): ~$120
- Memorystore (1GB standard): ~$50
- GCS + egress: ~$20-50
- Cloud Tasks + Cloud Scheduler: ~$5
- Cloud Monitoring + Logging: ~$50-100 (first 50GB logs free)
- Artifact Registry + Secret Manager: ~$10

Estimated total: ~$400-600/month, comparable or slightly lower. The 50k credits cover this entirely for 4-7+ years.

## Risks and how to mitigate

| Risk | Mitigation |
|---|---|
| Workspaces slips past 3 weeks | Phase 0 work is non-disruptive; runway sits idle until ready. No pressure to rush workspaces. |
| LangGraph features the agent uses don't all exist in JS | Resolved: agent stays Python. |
| Drizzle introspection misses something Directus-specific | Phase 1 starts with a small route to validate. Both stacks alive in parallel during migration; rollback is per-route. |
| Cold starts on Cloud Run bite production | `min-instances=1` on the hot path (echo-api). Cost is small (~$20/mo per pinned instance). |
| DNS TTL not low enough at cutover time | Lower TTLs now in Phase 0 so they're propagated before Phase 2. |
| Data migration window | `pg_dump | pg_restore` for prod takes a known window. Communicate it. Rollback is "switch DNS back to DO." |

## Open questions

- Does anyone use the Directus admin UI for non-developer work? (Affects Phase 2 keep-or-drop.)
- What's the actual workspaces ship date? (Anchors Phase 1 start.)
- Should the frontend move to Next.js during the rewrite or stay Vite SPA on Cloud Run? (Decide at Phase 2 start; not urgent.)

## See also

- [`architecture.md`](architecture.md) — current setup
- [`triage-2026-05-14.md`](triage-2026-05-14.md) — the incident that triggered this plan
