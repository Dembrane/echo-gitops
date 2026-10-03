# Cutover: old stack to dembrane v3

Switches production on `dbr-echo-prod-k8s-cluster` from the old stack (Argo CD app `echo-prod`,
chart `helm/echo`: Python API, Dramatiq workers, Directus, Neo4j) to dembrane v3 (app
`dembrane-web-prod`, chart `helm/dembrane-web`). Both use the same DO managed Postgres and the
same Spaces bucket, so there is no data copy: the switch is which stack runs and which one the
hostnames reach. Downtime runs from step 4 (old stack stopped) to step 9 (dashboard and portal
DNS answered by v3).

Commands assume the prod context (`do-ams3-dbr-echo-prod-k8s-cluster`) and `argocd` logged in to
the prod Argo CD. Values changes are commits to `prod-v3`; Argo CD reads them on the next sync.

## Before the window

These change nothing customers see.

1. **Images.** A v3 release tag that includes the media auth change (v3 on Cloud Run fetches a
   Google ID token for media from the metadata server, which DigitalOcean does not have) and
   the held-contract fix in the migrate job (see "Release the contract"). Dembrane/echo's
   `70-deploy-prod` pushes `registry.digitalocean.com/dbr-cr/dembrane-web-*:<sha>` and commits
   the sha to `helm/dembrane-web/values-prod.yaml` on `prod-v3`.
2. **Database login and secrets.** Create the DO database user `echo_app`. Then build, seal and
   apply both secrets (`secrets/dembrane-web-prod-secrets.keys.md`):
   ```sh
   kubectl create namespace dembrane-web-prod
   ./secret-manager.sh web-prod seal
   kubectl apply -f secrets/sealed-dembrane-web-prod-secrets.yaml
   kubectl apply -f secrets/sealed-do-registry-secret-web-prod.yaml
   kubectl -n dembrane-web-prod get secret dembrane-web-prod-secrets do-registry-secret
   ```
   Commit the two sealed files to `prod-v3`.
3. **Register the app, do not sync it.** `kubectl apply -f argo/dembrane-web-prod.yaml`.
   Automated sync is off: the app shows OutOfSync and nothing runs. Lower the Cloudflare TTL of
   `dashboard`, `portal`, `api` and `directus` to 60 seconds a day ahead.

## The window

4. **Stop the old stack.** Let the old workers finish what they are processing (Grafana queue
   depth at 0), then stop self-heal so the scale-down sticks, and scale everything to 0:
   ```sh
   argocd app set echo-prod --sync-policy none
   kubectl -n echo-prod scale deployment --all --replicas=0
   ```
   The HPAs leave a Deployment at 0 alone. The database and bucket are now written by nobody.
5. **Sync v3 with the contract held.** `argocd app sync dembrane-web-prod`. The PreSync hook
   `dembrane-web-migrate` runs first with `MIGRATE_HOLD_CONTRACT=1`: expand migrations (index
   builds on `processing_status` take a lock, which is why this waits for step 4), the DBOS
   schema, the identity copy from Directus, grants to `echo_app`. The API, media, dashboard and
   portal roll out only if it succeeds; the PostSync hook `dembrane-web-smoke` then checks them
   in-cluster. Read both:
   `kubectl -n dembrane-web-prod logs job/dembrane-web-migrate` and `.../job/dembrane-web-smoke`.
6. **Start the worker.** Commit `worker.replicas: 2` in `values-prod.yaml`, sync. The smoke hook
   now also waits for a heartbeat from a worker of this release (`/ready/worker?release=`).
7. **Move the hostnames.** Delete the old ingress (self-heal is off, so it stays deleted; the
   ClusterIssuer `letsencrypt-prod` and the old certificate secret stay), then turn on v3's:
   ```sh
   kubectl -n echo-prod delete ingress echo-ingress
   ```
   Commit `ingress.enabled: true` and `ingress.legacyDirectus.enabled: true`, sync.
   `api.dembrane.com` and `directus.dembrane.com` already resolve to the cluster's load balancer
   (206.189.240.151), so their certificates issue within minutes:
   `kubectl -n dembrane-web-prod get certificate`.
8. **Smoke through the load balancer.**
   ```sh
   curl -s https://api.dembrane.com/health          # "release":"<sha>"
   curl -s https://api.dembrane.com/ready
   curl -s "https://api.dembrane.com/ready/worker?release=<sha>"
   for h in dashboard portal; do
     curl -sk --resolve $h.dembrane.com:443:206.189.240.151 https://$h.dembrane.com/runtime-config.js
   done
   curl -sI https://directus.dembrane.com/assets/<a known avatar id>   # 200 from the API
   ```
   Sign in with a staff account and a QA account (password and Google), open a project, record
   a short conversation on the portal and watch it transcribe, open a report.
9. **Dashboard and portal DNS.** In Cloudflare, replace the `dashboard` and `portal` CNAMEs to
   `cname.vercel-dns.com` with A records to 206.189.240.151, DNS only (not proxied). Their
   certificates issue by HTTP-01 once DNS answers; until then browsers see the ingress default
   certificate, so watch `kubectl -n dembrane-web-prod get certificate` and retest step 8
   without `--resolve`.
10. **Vercel.** Once both hosts serve v3 with valid certificates, remove `dashboard.dembrane.com`
    and `portal.dembrane.com` from the Vercel projects so Vercel stops serving and renewing them.
    Keep the projects and their last deployments for rollback.

The old stack stays as it is now: Argo app registered, self-heal off, every Deployment at 0, no
ingress. That is the rollback.

## After the window

11. **GitOps on main.** Merge the `prod-v3` PR into `main`, then point the app at main and turn
    automated sync on (edit `argo/dembrane-web-prod.yaml` the same way and apply it):
    ```sh
    argocd app set dembrane-web-prod --revision main --sync-policy automated --self-heal --auto-prune
    ```
    In Dembrane/echo set the repository variables `GITOPS_PROD_BRANCH=main` and
    `PROD_WAIT_FOR_ROLLOUT=true`, so each release bumps main and waits for the new release on
    `api.dembrane.com` before it announces.
12. **Monitoring.** In `helm/monitoring/values-prod.yaml` replace the `directus` probe (it now
    redirects; probe `https://api.dembrane.com/ready` instead) and set `dashboards.namespace` to
    `dembrane-web-prod`.

## Rollback

Possible until the contract is released: the old stack's tables are all still there.

1. v3 off the hostnames and out of the queue: commit `ingress.enabled: false`,
   `ingress.legacyDirectus.enabled: false`, `worker.replicas: 0`, sync (prune removes the
   ingresses). Faster by hand: `kubectl -n dembrane-web-prod delete ingress --all` and
   `kubectl -n dembrane-web-prod scale deployment dembrane-web-worker --replicas=0`.
2. Cloudflare: `dashboard` and `portal` back to CNAME `cname.vercel-dns.com`; re-add the domains
   in Vercel.
3. Old stack back: `argocd app set echo-prod --sync-policy automated --self-heal --auto-prune`,
   then `argocd app sync echo-prod`. The sync recreates `echo-ingress` and the replica counts
   from `helm/echo/values-prod.yaml`.

What v3 wrote in between stays in the shared tables and the old stack reads it, with one gap:
people who signed up or changed a password on v3 exist only in v3's auth tables, not in
Directus.

## Release the contract

Only when rollback is no longer wanted. Contract migrations drop tables only the old stack
read (`0012_contract_dead_features`: the old library, segments and LightRAG, about 21 GB).

1. Retire the old stack without losing the cluster-scoped objects its chart owns (the
   ClusterIssuer `letsencrypt-prod` every certificate here uses, and the PriorityClasses):
   `argocd app delete echo-prod --cascade=false`, then `kubectl delete namespace echo-prod`.
   The ClusterIssuer and PriorityClasses remain, unmanaged; move the ClusterIssuer into a chart
   that stays.
2. Archive what the contract drops, from Dembrane/echo with gcloud signed in:
   `DATABASE_URL=<MIGRATION_DATABASE_URL> dembrane/platform/packages/db/scripts/archive-tables.sh`.
   It records the archive in `drizzle.contract_archive`.
3. Apply the held contract. Setting `migrate.holdContract: false` alone does nothing on this
   database: drizzle applies only migrations newer than the newest one applied, and
   `0013_expand_session_devices` (newer than 0012) was applied with 0012 held, so 0012 is
   skipped and the archive check, which uses the same rule, passes silently. Apply it with a
   migrate build that runs held contract migrations by name, or by hand as the owner: run the
   0012 SQL in one transaction and insert its row into `drizzle.__drizzle_migrations` (hash:
   sha256 of the file, `created_at` 1790586541043, its journal `when`).
4. Then commit `migrate.holdContract: false`, so later contract migrations run on deploy once
   their archive is recorded.
