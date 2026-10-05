@Dembrane, @spashii needs your help!

## done (2026-08-13)
- ~~CI validations~~ → `.github/workflows/validate.yml`: `helm lint` and
  `helm template` for all five Argo render combinations, `kubeconform` on the
  output, `terraform fmt`/`validate`, and a check that every Argo Application
  tracks `main`. It caught a duplicate-annotation bug in the monitoring ingress
  on its first run.
- ~~Neo4j~~ deleted (deployment, service, PVC, the `echo-critical` PriorityClass
  that existed only for it, and its committed password). Zero references in
  `server/`, `agent/` or `frontend/` confirmed before removal.
- ~~Grafana `adminPassword: "admin"` in values~~ deleted. It was dead config; the
  live value comes from the SealedSecret.

## still open, highest value first
- **protect `main`** (see the section below; still unprotected as of 2026-08-13
  while Argo syncs prod from it with prune + selfHeal)
- **one Argo, app-of-apps** — Application CRs are still applied by hand, which is
  the drift bug from `docs/triage-2026-05-14.md`. Note `docs/migration-plan.md`
  decision 6 ("don't adopt app-of-apps") is void: the repo is staying and the
  target is now OVHcloud, not GCP Cloud Run.
- `imagePullPolicy: Always` on every deployment while image tags are immutable
  git SHAs. Puts the registry in the pod startup path for no benefit.

## infra
- add Azure LLMs
- add Runpod Servvice (or use Az Serverless / Google Cloud Run)
- setup Secrets using tf
- frontend secrets managed by vercel is not ideal

## helm
- setup liveness and readiness probes for workers-* deployments (using dramatiq)
- resource optimization for values[-prod?].yaml 

## monitoring
- need better dashboards (logs per deployment, metrics per deployment)
- setup alerting rules for critical services

## protect main branch

## remove %2Cerror%2C from directus logs lol

## [2025-10-13 00:07:49,270] [PID 8] [Thread-2] [dramatiq.middleware.time_limit.TimeLimit] [WARNING] Time limit exceeded. Raising exception in worker t │
│ echo-worker-cpu-65bfd78f46-z6x2p WARNING:dramatiq.middleware.time_limit.TimeLimit:Time limit exceeded. Raising exception in worker thread 140447687100096.                            │
│ echo-worker-cpu-65bfd78f46-z6x2p [2025-10-13 00:07:49,277] [PID 8] [Thread-5] [status] [INFO] task_run_etl_pipeline.failed  - 300113                                                  │
│ echo-worker-cpu-65bfd78f46-z6x2p INFO:status:task_run_etl_pipeline.failed  - 300113                                                                                                   │
│ echo-worker-cpu-65bfd78f46-z6x2p [2025-10-13 00:07:49,356] [PID 8] [Thread-5] [status.task_run_etl_pipeline] [ERROR] 5098277  (duration: 300.113s) (started: 5098240)                 │
│ echo-worker-cpu-65bfd78f46-z6x2p ERROR:status.task_run_etl_pipeline:5098277  (duration: 300.113s) (started: 5098240)                                   