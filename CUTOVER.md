# Cutover: old stack to dembrane v3

Switches production on `dbr-echo-prod-k8s-cluster` from the old stack (Argo CD app `echo-prod`,
chart `helm/echo`: Python API, Dramatiq workers, Directus, Neo4j) to dembrane v3 (app
`dembrane-web-prod`, chart `helm/dembrane-web`). Both use the same DO managed Postgres and the
same Spaces bucket, so there is no data copy: the switch is which stack runs and which one the
hostnames reach. Downtime runs from step 4 (old stack stopped) to step 9 (dashboard and portal
DNS answered by v3).

Commands assume the prod context (`do-ams3-dbr-echo-prod-k8s-cluster`) and `argocd` logged in to
the prod Argo CD. Values changes are commits to `prod-v3`; Argo CD reads them on the next sync.

## Check every sync

A sync can report `Succeeded` within seconds and change nothing: seen twice in the rehearsal, each
time on the first sync after a change Argo CD had not compared yet (a new commit, a resource
deleted by hand). So before a sync, wait until the app shows `OutOfSync`
(`argocd app get <app> --hard-refresh`), and after it, read the cluster, not the sync result:
the release in `/health`, the ingresses, the worker's replica count. If they are not what the
step expects, sync again.

## Rules for the window

- **When.** Sunday 02:00 to 08:00 Amsterdam time: in four weeks of PostHog data no recording
  started in those hours, and the quietest day of the week follows. Saturday night is not quiet
  (recordings from the United States until about 02:00).
- **Go.** Start step 4 only when steps 1 to 3 and every check in step 0 are done, the old stack
  is healthy (a rollback must return to a known state), and no audio arrived in the last 15
  minutes (`conversation_chunk.created_at`).
- **Freeze.** No merge into Dembrane/echo `main` from step 4 to step 10: each merge runs
  `65-deploy-echo-next`, which commits to `prod-v3`, the branch production reads.
- **One operator.** Every command against production comes from one session. Automated sync on
  `dembrane-web-prod` stays off; each sync is run by hand and checked (see "Check every sync").
- **Stop.** Roll back when the migrate job fails twice, when step 8 fails and one attempt does
  not find the cause, or when step 8 has not passed by 07:00.
- **Point of no return.** The first customer write on v3 after step 9. Before it, the rollback
  loses nothing. After it, sessions and two-factor settings made on v3 are lost on a rollback,
  and a fix forward is almost always the better choice.

## Before the window

These change nothing customers see.

0. **Checks, read only.** On the production database, in a read-only transaction:
   ```sql
   select tableowner, count(*) from pg_tables where schemaname = 'public' group by 1;
   select lower(email), count(*) from directus_users group by 1 having count(*) > 1;
   select pg_size_pretty(pg_total_relation_size('processing_status'));
   show max_connections;
   ```
   One owner (the `MIGRATION_DATABASE_URL` login), or the grants at the end of the migrate job
   fail after the migrations have committed. No rows from the second query, or two accounts
   collapse into one in the identity copy. The size bounds the index build in step 5. The
   connection limit must exceed the 65 in `values-prod.yaml`.
   In the Google OAuth client, add `https://api.dembrane.com/api/auth/callback/google` as a
   redirect URI, or Google sign-in fails at step 8.
   Tell customers: everyone is signed out at the cutover, two-factor has to be set up again,
   and the iOS app cannot sign in until its next version.

1. **Images.** A v3 release tag that includes the media auth change (v3 on Cloud Run fetches a
   Google ID token for media from the metadata server, which DigitalOcean does not have) and
   the held-contract fix in the migrate job (see "Release the contract"); both are in main since
   `24a60749` and `b0a950ec`. A tag push alone runs checks only (the repository variable
   `PROD_DEPLOY_ON_TAG` is unset on purpose), so start the job by hand and approve it in the
   `prod` environment:
   ```sh
   git tag v3.0.0 <full 40-character sha on main> && git push origin v3.0.0
   gh workflow run platform.yml -R Dembrane/echo --ref main -f target=prod -f tag=v3.0.0
   ```
   `70-deploy-prod` pushes `registry.digitalocean.com/dbr-cr/dembrane-web-*:<sha>` and commits
   the sha to `helm/dembrane-web/values-prod.yaml` on `prod-v3`. It holds no cluster access, and
   with automated sync off the commit only makes the app OutOfSync.
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
   `S3_ACCESS_KEY` and `S3_SECRET_KEY` are the Spaces key `v3-prod-uploads`, which reaches only
   `dbr-echo-prod-uploads`; the old stack's key reaches every bucket in the account, the
   backups and the Terraform state among them, and stays out of v3.
   Prove the pull secret before the window, once step 1 has pushed the images:
   ```sh
   kubectl -n dembrane-web-prod run pull-test --restart=Never --image=registry.digitalocean.com/dbr-cr/dembrane-web-api:<sha> \
     --overrides='{"spec":{"imagePullSecrets":[{"name":"do-registry-secret"}]}}' --command -- true
   kubectl -n dembrane-web-prod get pod pull-test   # Completed, not ImagePullBackOff
   kubectl -n dembrane-web-prod delete pod pull-test
   ```
   Make one Vertex call with the key in `GCP_SA_JSON` against project `dembrane-web-prod`: no
   deployment has used that project yet, and the smoke hook makes no model call.
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
   Before the workers go, save what the Dramatiq queues still hold (run in a worker pod, which
   reaches the private Valkey): a rollback replays these against rows v3 may have changed, so
   the copy is what lets them be replayed by hand instead.
   ```sh
   kubectl -n echo-prod exec deploy/echo-worker -- python -c 'import os, json, redis; r = redis.from_url(os.environ["REDIS_URL"]); print(json.dumps({q: {k.decode(): v.decode() for k, v in r.hgetall(f"dramatiq:{q}.msgs").items()} for q in ["network", "cpu", "network.DQ", "cpu.DQ"]}))' > dramatiq-leftover.json
   ```
4b. **Back up the database.** The old stack is stopped, so this copy is the last state it wrote.
   `backup/db-backup-job.yaml` runs on the echo-next cluster (context
   `do-ams3-dbr-echo-dev-k8s-cluster`), reads production through one snapshot and uploads the
   dump, its table of contents, exact row counts and a hash to the private Space
   `dbr-echo-prod-backups` under `postgres/<stamp>/`. It leaves out the data of
   `processing_status`, `directus_revisions` and `lightrag_*` (35 of 43 GB; the tables are kept,
   empty); DigitalOcean's own daily backup still has them. The job reads a secret `backup` in
   namespace `db-backup`: `PROD_DATABASE_URL`, `ca.crt` (`doctl databases get-ca`), and the
   Space key `prod-backups-writer`, which can touch only that bucket (`AWS_ACCESS_KEY_ID`,
   `AWS_SECRET_ACCESS_KEY`). Delete the namespace afterwards: it holds the database login.
   ```sh
   kubectl --context do-ams3-dbr-echo-dev-k8s-cluster apply -f backup/db-backup-job.yaml
   kubectl --context do-ams3-dbr-echo-dev-k8s-cluster -n db-backup logs -f job/db-backup -c dump
   ```
   Go on only when the upload container has listed the four files. Rehearsed on 2026-10-08:
   the dump is 2.1 GB and takes about 8 minutes; `backup/db-restore-job.yaml` restored it into
   an empty database in about 4 minutes with every one of 95 tables at the dump's row count.
   To restore, give the same secret `RESTORE_DATABASE_URL` and `restore-ca.crt`, and set the
   folder in the job. The restore job has only run into an empty database: restore into a new
   database on the same cluster and point both stacks' URLs at it, never over `defaultdb`.
   DigitalOcean's point-in-time recovery (a fork of the cluster at a chosen minute) is the
   second line, and the only one that still holds the tables the dump leaves out.
5. **Sync v3 with the contract held.** `argocd app sync dembrane-web-prod`. The PreSync hook
   `dembrane-web-migrate` runs first with `MIGRATE_HOLD_CONTRACT=1`: expand migrations (index
   builds on `processing_status` take a lock, which is why this waits for step 4), the DBOS
   schema, the identity copy from Directus, grants to `echo_app`. The API, media, dashboard and
   portal roll out only if it succeeds; the PostSync hook `dembrane-web-smoke` then checks them
   in-cluster. All pending migrations run in one transaction, and the job is killed at
   `migrate.activeDeadlineSeconds`: an overrun rolls everything back and a retry starts from
   zero, so `values-prod.yaml` sets 3600 for the cutover. Read both:
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
   without `--resolve`. cert-manager's self-check has been failing since step 7 and backs off to
   about 16 minutes between tries; delete the pending challenges so the order makes new ones at
   once: `kubectl -n dembrane-web-prod delete challenges.acme.cert-manager.io --all`.
10. **Vercel.** Once both hosts serve v3 with valid certificates, remove `dashboard.dembrane.com`
    and `portal.dembrane.com` from the Vercel projects so Vercel stops serving and renewing them.
    Keep the projects and their last deployments for rollback.

The old stack stays as it is now: Argo app registered, self-heal off, every Deployment at 0, no
ingress. That is the rollback.

## After the window

11. **GitOps on main.** Not on the cutover night: do it once v3 has run for some days. Merge
    the `prod-v3` PR into `main`, then move the app in three steps, so a stale cached revision
    cannot sync by itself (edit `argo/dembrane-web-prod.yaml` the same way and apply it):
    ```sh
    argocd app set dembrane-web-prod --revision main
    argocd app get dembrane-web-prod --hard-refresh
    argocd app diff dembrane-web-prod        # nothing but the revision
    ```
    Automated sync comes later still, after three releases synced by hand have gone well:
    ```sh
    argocd app set dembrane-web-prod --sync-policy automated --self-heal --auto-prune
    ```
    In Dembrane/echo set the repository variables `GITOPS_PROD_BRANCH=main` and
    `PROD_WAIT_FOR_ROLLOUT=true`, so each release bumps main and waits for the new release on
    `api.dembrane.com` before it announces.
    `GITOPS_PROD_BRANCH` also names the branch echo-next's tag is written to, so on the dev
    cluster point `dembrane-web-dummy` at main in the same step
    (`argocd app set dembrane-web-dummy --revision main`).
12. **Monitoring.** In `helm/monitoring/values-prod.yaml` replace the `directus` probe (it now
    redirects; probe `https://api.dembrane.com/ready` instead) and set `dashboards.namespace` to
    `dembrane-web-prod`.

## Rollback

Possible until the contract is released: the old stack's tables are all still there.

1. v3 off the hostnames and out of the queue, by hand:
   `kubectl -n dembrane-web-prod delete ingress --all` and
   `kubectl -n dembrane-web-prod scale deployment dembrane-web-worker --replicas=0`.
   Then commit `ingress.enabled: false`, `ingress.legacyDirectus.enabled: false` and
   `worker.replicas: 0` so the next sync does not put them back. A sync alone does not remove
   the ingresses (the app has no prune), and while they exist ingress-nginx keeps serving them
   and ignores the old stack's recreated `echo-ingress`.
2. Cloudflare: `dashboard` and `portal` back to CNAME `cname.vercel-dns.com`; re-add the domains
   in Vercel.
3. Old stack back: `argocd app set echo-prod --sync-policy automated --self-heal --auto-prune`,
   then `argocd app sync echo-prod`. The sync recreates `echo-ingress` and the replica counts
   from `helm/echo/values-prod.yaml`.

What v3 wrote in between stays in the shared tables and the old stack reads it. v3 also writes
new users and password hashes to `directus_users`, so sign-ups and password changes survive;
sessions and two-factor settings made on v3 do not. Messages saved in step 4 are replayed by
hand, after a look at what v3 did to their rows.

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
