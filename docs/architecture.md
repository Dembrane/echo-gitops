# Architecture

> **Update 2026-05-15:** this doc describes the GitOps setup as it stood on 2026-05-14 (the day the [triage](triage-2026-05-14.md) was done). Since then, significant fixes shipped (drift closed on prod monitoring, dev monitoring deployed for the first time, multiple cruft cleanups). See [migration-plan.md](migration-plan.md) "Day 0 progress" for the running list. **The setup itself is being phased out in 2-3 months in favor of GCP Cloud Run** — see migration-plan.md for the target architecture and reasoning. This doc is preserved as the as-built reference for the system being replaced.

How the GitOps setup is wired today, where the gaps are, and what "app of apps" would change.

## The shortest possible summary

Three DigitalOcean Kubernetes clusters (`prod`, `dev`, `testing`). Each runs its own ArgoCD. ArgoCD polls `github.com/dembrane/echo-gitops` and reconciles two Helm charts (`helm/echo` and `helm/monitoring`) into the appropriate namespaces. Terraform provisions everything below the cluster (nodes, Postgres, Redis, Spaces, registry) plus the initial Kubernetes namespaces and the initial ArgoCD `Application` CRs.

The one thing that **isn't** GitOps-managed: the `Application` CRs themselves. Once Terraform creates them, the files under `argo/` in this repo are advisory — editing them does not change the cluster. That's the gap "app of apps" closes.

---

## 1. App of apps

### The concept

An ArgoCD `Application` tells ArgoCD: "watch this path in this git repo, render the manifests, and keep this namespace matching them." Normal Applications point at a Helm chart or a Kustomize overlay.

An **app of apps** is one special root Application that points at a directory full of *other Application YAMLs*. Whenever you change a file in that directory, the root app re-applies it, which updates the live Application CR, which then re-syncs its own workloads. Application manifests become just another thing GitOps reconciles.

### Without app of apps (current setup)

```
                  ┌─────────────────────────────────────────────┐
                  │  git: dembrane/echo-gitops                  │
                  │                                             │
                  │  argo/echo-monitoring-prod.yaml             │
                  │    targetRevision: main          ◄── edited │
                  │                                             │
                  │  helm/monitoring/...             ◄── new code
                  └──────────────────┬──────────────────────────┘
                                     │ ArgoCD watches the path
                                     │ INSIDE the Application
                                     │ (helm/monitoring) — NOT
                                     │ the Application YAML itself
                                     ▼
   ┌──────────────────────────────────────────────────────┐
   │ Prod cluster, namespace=argocd                       │
   │                                                      │
   │  Application/echo-monitoring-prod  (a CR in K8s)     │
   │    targetRevision: feature/monitoring_prod ◄── stale │
   │                                                      │
   │  This is what ArgoCD actually reads.                 │
   │  Editing the file in git does not change this.       │
   └──────────────────────────────────────────────────────┘
```

The Application CR was created **once** by `kubectl apply -f argo/...` (likely from Terraform's kubernetes provider). After that, the file in git and the live CR drift independently. Nothing reconciles them.

### With app of apps

```
                 ┌─────────────────────────────┐
                 │  git: argo/                 │
                 │   ├ echo-prod.yaml          │
                 │   ├ echo-monitoring-prod.yml│
                 │   └ ...                     │
                 └──────────────┬──────────────┘
                                │
                                ▼
                 ┌─────────────────────────────┐
                 │ Application/root            │   ◄── applied ONCE by
                 │   path: argo/               │       hand or by Terraform
                 │   automated sync            │
                 └──────────────┬──────────────┘
                                │ applies every YAML in argo/
                                ▼
                 ┌─────────────────────────────┐
                 │ Application/echo-prod        │
                 │ Application/echo-monitoring-*│  ◄── now kept in sync
                 │ Application/...              │       with git automatically
                 └──────────────┬──────────────┘
                                │
                                ▼
                          actual workloads
```

### Trade-offs

- **Cost of adopting:** one bootstrap Application per cluster, plus a written "don't break the root app" convention. Root-app misconfiguration becomes a single point of failure.
- **Cost of not adopting:** every Application YAML change requires a manual `kubectl apply`. Forgetting it produces silent drift (exactly the bug discovered on 2026-05-14: 8 months of monitoring changes never deployed).
- **For 6 Applications across 3 clusters,** the manual-apply cost is small *if everyone remembers it*. It clearly didn't happen here. Adoption gives durability at the cost of one extra concept.

`ApplicationSet` is a related ArgoCD feature for templating Apps across environments. Overkill at this scale.

---

## 2. The actual setup, layer by layer

### Layer 1 — Source of truth

```
GitHub: github.com/dembrane/echo-gitops (branch: main)

  argo/                  ← ArgoCD Application manifests (one per app)
    echo-dev.yaml              targetRev=HEAD,  path=helm/echo,        ns=echo-dev
    echo-testing.yaml          targetRev=main,  path=helm/echo,        ns=echo-testing
    echo-prod.yaml             targetRev=main,  path=helm/echo,        ns=echo-prod
    echo-monitoring-dev.yaml   targetRev=HEAD,  path=helm/monitoring,  ns=echo-dev
    echo-monitoring-prod.yaml  targetRev=main,  path=helm/monitoring,  ns=monitoring
    ai-infra-secrets-dev.yaml  targetRev=...,   path=ai-infra/k8s,     ns=argocd

  helm/echo/             ← Helm chart for app workloads
                           (api, agent, worker, directus, neo4j)
    values.yaml, values-prod.yaml, values-testing.yaml

  helm/monitoring/       ← Helm chart for observability
                           (prometheus, grafana, loki, alertmanager,
                           promtail, node-exporter)
    values.yaml, values-prod.yaml

  infra/                 ← Terraform: DO cluster, db, redis, spaces,
                           k8s namespaces, sealed-secrets controller
  ai-infra/              ← Terraform: GCP Vertex AI endpoints + IAM
  secrets/               ← SealedSecrets (encrypted; safe to commit)
```

### Layer 2 — DigitalOcean managed infrastructure

```
DigitalOcean (region: ams3)

  ┌─ 3 Kubernetes clusters (DOKS, v1.32) ─┐
  │                                       │
  │   dbr-echo-prod-k8s-cluster           │  9 nodes
  │     ├ default-pool (6)                │
  │     └ monitoring-devops-pool (3)      │
  │   dbr-echo-dev-k8s-cluster            │  smaller
  │   dbr-echo-testing-k8s-cluster        │  smaller
  └───────────────────────────────────────┘

  ┌─ Managed services (one set per env) ──┐
  │   PostgreSQL                          │  echo-api / Directus DB
  │   Redis                               │  caches, dramatiq queue,
  │                                       │  APScheduler state
  │   Spaces (S3-compatible)              │  audio chunks, backups
  └───────────────────────────────────────┘

  Container Registry  (registry.digitalocean.com/dbr-cr)
    └ dbr-echo-api, dbr-echo-agent, dbr-echo-worker, dbr-directus, ...
```

### Layer 3 — Inside each cluster

```
                  ┌──────────────────── PROD cluster ─────────────────────┐
                  │                                                       │
                  │  ns=argocd            Application CRs (5 total):      │
                  │    ArgoCD              ├ echo-prod          → echo-prod ns
                  │    controllers         ├ echo-monitoring-prod → monitoring ns
                  │                        ├ echo-k6-prod       → loadtesting (Missing)
                  │                        ├ echo-k6-dev        → loadtesting (Missing)
                  │                        └ ai-infra-secrets-dev → argocd ns
                  │                                                       │
                  │  ns=echo-prod         Helm-rendered from helm/echo    │
                  │    Deploy/echo-api               (Running)            │
                  │    Deploy/echo-agent             (ImagePullBackOff)   │
                  │    Deploy/echo-directus          (Running)            │
                  │    Deploy/echo-worker            (Running)            │
                  │    StatefulSet/echo-neo4j        (Running)            │
                  │    HPAs, PriorityClasses, SealedSecrets               │
                  │                                                       │
                  │  ns=monitoring        Helm-rendered from helm/monitoring
                  │    Deploy/prometheus             (1 Running)          │
                  │    Deploy/grafana                (Running)            │
                  │    Deploy/loki                   (Running)            │
                  │    Deploy/alertmanager           (Running, old config)│
                  │    DaemonSet/promtail            (8/9 — gap on 6c3vu) │
                  │    DaemonSet/node-exporter       (8/9 — same)         │
                  │    ConfigMaps: prometheus rules, alertmanager.yml,    │
                  │                grafana dashboards, loki config        │
                  │                                                       │
                  │  ns=ingress-nginx     Ingress controller              │
                  │  ns=cert-manager      Cert issuance (Let's Encrypt)   │
                  │  ns=kube-system       Cilium CNI, CoreDNS, csi-do     │
                  └───────────────────────────────────────────────────────┘

                  ┌──────────────────── DEV cluster ──────────────────────┐
                  │                                                       │
                  │  ns=argocd            Application CRs (1 total):      │
                  │    ArgoCD              └ echo-dev → echo-dev ns       │
                  │                                                       │
                  │  ns=echo-dev          Helm-rendered (api, agent, ...) │
                  │                                                       │
                  │  ns=monitoring        EMPTY                           │
                  │    (echo-monitoring-dev Application never applied)    │
                  └───────────────────────────────────────────────────────┘

                  ┌──────────────────── TESTING cluster ──────────────────┐
                  │                                                       │
                  │  ns=argocd            Application CRs (1 total):      │
                  │    ArgoCD              └ echo-testing → echo-testing  │
                  │                                                       │
                  │  ns=echo-testing      Helm-rendered                   │
                  │  ns=monitoring        EMPTY (same gap as dev)         │
                  └───────────────────────────────────────────────────────┘
```

### Layer 4 — How a deploy flows today

```
   developer pushes commit to main
                │
                ▼
   ┌─────────────────────────────┐
   │ helm/echo/values-*.yaml or  │
   │ helm/monitoring/values-*.yaml│
   │ changes in git              │
   └──────────────┬──────────────┘
                  │ each cluster's ArgoCD polls every ~3 min
                  ▼
   ┌─────────────────────────────┐
   │ ArgoCD controller diffs     │      automated.prune: true
   │ live vs. desired Helm output│      automated.selfHeal: true
   │ and applies the diff        │      → applies the diff
   └──────────────┬──────────────┘
                  │
                  ▼
   ┌─────────────────────────────┐
   │ kube-apiserver applies      │
   │ Deployments / ConfigMaps /  │
   │ DaemonSets / SealedSecrets  │
   └─────────────────────────────┘
```

Note what's **not** in this loop: the `argo/*.yaml` files themselves. They live in git but no controller reads them after the initial `kubectl apply`. That's the app-of-apps hole.

### Layer 5 — Outside the cluster

```
   Terraform (run by hand from your laptop)
     │
     │ creates / updates
     ▼
   • DO cluster + node pools          ─┐
   • DO managed Postgres/Redis/Spaces  │ provider: digitalocean
   • DO Container Registry             ─┘
   • K8s namespaces                    ─┐
   • Sealed Secrets controller         │ provider: kubernetes / helm
   • Initial ArgoCD install + Apps     ─┘
   • GCP Vertex AI endpoints (ai-infra) → provider: google

   Vercel  (separate; not in this repo)
     │
     └ frontends: dashboard.dembrane.com, portal.dembrane.com, ...
```

---

## 3. The single end-to-end picture

```
┌────────────────┐         ┌──────────────────────────────────────────────────────┐
│ developer      │         │  GitHub: dembrane/echo-gitops (main)                 │
│  pushes commit │ ──────► │   argo/    helm/echo/    helm/monitoring/   infra/   │
└────────────────┘         └──────────────────────────────────────────────────────┘
                                  │ (no app-of-apps; argo/ not auto-applied)
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼ poll                    ▼ poll                    ▼ poll
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│ ArgoCD prod  │         │ ArgoCD dev   │         │ ArgoCD test  │
│  on DOKS     │         │  on DOKS     │         │  on DOKS     │
└──────┬───────┘         └──────┬───────┘         └──────┬───────┘
       │ sync helm/echo         │ sync helm/echo         │ sync helm/echo
       │ sync helm/monitoring   │ (no monitoring app)    │ (no monitoring app)
       ▼                        ▼                        ▼
   echo-prod ns             echo-dev ns              echo-testing ns
   monitoring ns            (monitoring ns empty)    (monitoring ns empty)
       │                        │                        │
       └──────────┬─────────────┴────────────────────────┘
                  ▼
   DO managed Postgres / Redis / Spaces / Container Registry
```

---

## Decision: adopt app of apps?

Two reasonable paths:

1. **Stay manual.** Document in `AGENTS.md` / `README.md`: "if you change a file under `argo/`, you must `kubectl apply -f` it on the right cluster." Low ceremony, but the bug found on 2026-05-14 shows the convention is easy to forget when nobody touches `argo/` for months.

2. **Minimal app of apps.** One root `Application` per cluster watching `argo/`. Apply each root manually one time (or via Terraform). After that, all Application changes are GitOps-managed. Cost: one extra concept, plus discipline to not break the root.

Open. Not urgent — option 1 can ship the current pending monitoring changes by re-applying the two Application YAMLs.
