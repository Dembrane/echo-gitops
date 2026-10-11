# Cutover: old stack to dembrane v3

Switches production on `dbr-echo-prod-k8s-cluster` from the old stack (Argo CD app `echo-prod`,
chart `helm/echo`: Python API, Dramatiq workers, Directus, Neo4j) to dembrane v3 (app
`dembrane-web-prod`, chart `helm/dembrane-web`). Both use the same DO managed Postgres and the
same Spaces bucket, so there is no data copy: the switch is which stack runs and which one the
hostnames reach. Downtime runs from step 4 (old stack stopped) to step 9 (dashboard and portal
DNS answered by v3).

Values changes are commits to `prod-v3`; Argo CD reads them on the next sync.

## Tools and logins

- `kubectl`, `argocd` 2.14.4 (the version both clusters run), `kubeseal` 0.28.0, `doctl`, `gh`.
- `argocd` runs in core mode: no login, it talks to the cluster through a kubeconfig whose only
  context is the cluster and whose namespace is `argocd`. Make one per cluster and export it
  before the commands below; with only production in the file, no command can reach the other
  cluster by mistake.
  ```sh
  kubectl config view --minify --flatten --kubeconfig ~/.kube/config --context do-ams3-dbr-echo-prod-k8s-cluster > ~/.kube/prod-argocd.yaml
  KUBECONFIG=~/.kube/prod-argocd.yaml kubectl config set-context --current --namespace=argocd
  export KUBECONFIG=~/.kube/prod-argocd.yaml
  argocd --core app list
  ```
- `gh` needs the token of a Dembrane member, and step 1 needs a checkout of Dembrane/echo.
- Every `kubectl -n <namespace>` below names its namespace: the kubeconfig's default is `argocd`.

## What has been run

On the test cluster (old stack `echo-dev`, v3 `dembrane-web-dummy`, one shared database), with
the commands as written here, on 2026-10-11: steps 4 to 8 (not 4b) and rollback steps 1 and 3. After the
rollback the old stack signed a user in, read organisations and projects and wrote a
conversation on the database v3 had migrated and used; after steps 4 to 8, v3 did the same.
The migrate job of the release also ran against a copy of production's schema (no data): twelve
migrations applied, the baseline adopted, a second run a no-op.

Not run anywhere: step 9 (DNS and the certificates that follow it), step 10, and the migrate
job on production's data, where the index on `processing_status` (3.3 million rows) is the only
slow statement. Step 4b last ran on 2026-10-08.

The test cluster differs in one way that matters for a rehearsal: its old stack's Argo app
ignores the replica counts of `echo-api`, `echo-worker` and `echo-worker-cpu`, so after a
rollback sync there they stay at 0 and have to be scaled by hand. Production's app has no such
rule; its sync sets every count.

## Check every sync

A sync can report `Succeeded` within seconds and change nothing, on the first sync after a
change Argo CD had not compared yet (a new commit, a resource deleted by hand). So before a
sync, refresh until the app shows `OutOfSync` (`argocd --core app get <app> --hard-refresh`),
and after it, read the cluster, not the sync result: the release in `/health`, the ingresses,
the worker's replica count. If they are not what the step expects, sync again.

## Rules for the window

- **When.** Sunday 02:00 to 08:00 Amsterdam time: in four weeks of PostHog data no recording
  started in those hours, and the quietest day of the week follows. Saturday night is not quiet
  (recordings from the United States until about 02:00).
- **Go.** Start step 4 only when steps 0 to 3 are done, the old stack is healthy (a rollback
  must return to a known state), and no audio arrived in the last 15 minutes
  (`conversation_chunk.created_at`).
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
   select lower(email), count(*) from directus_users where email is not null group by 1 having count(*) > 1;
   select pg_size_pretty(pg_total_relation_size('processing_status'));
   show max_connections;
   select to_regclass('drizzle.__drizzle_migrations'), to_regclass('public.auth_user'),
          to_regclass('public.map_group');
   select extname from pg_extension where extname = 'vector';
   ```
   One owner (the `MIGRATION_DATABASE_URL` login), or the grants at the end of the migrate job
   fail after the migrations have committed. No rows from the second query, or two accounts
   collapse into one in the identity copy. The size bounds the index build in step 5. The
   connection limit must exceed the 65 in `values-prod.yaml`. The three `to_regclass` values
   are null: all pending migrations run in one transaction and create their tables without
   `IF NOT EXISTS`, so a table left by an earlier attempt fails every retry the same way.
   `vector` is installed.
   In the Google OAuth client, add `https://api.dembrane.com/api/auth/callback/google` as a
   redirect URI before `AUTH_GOOGLE_CLIENT_ID` and `AUTH_GOOGLE_CLIENT_SECRET` go into the
   secret; without them v3 offers no Google sign-in, and those users sign in by email code.
   Tell customers: everyone is signed out at the cutover, two-factor has to be set up again
   (v3 stores its secret in another form, so it is not copied), and the iOS app cannot sign in
   until its next version. The Directus admin app, its dashboards and its two manual email
   flows go with Directus, and so does every Directus static token.

1. **Images.** The release commit `fa8503af31b46c8e80f0251c6269dd2a3a028378` includes the media
   auth change (v3 on Cloud Run fetches a Google ID token for media from the metadata server,
   which DigitalOcean does not have) and the held-contract fix in the migrate job; both are in
   main since `24a60749` and `b0a950ec`. Its images are in the registry (the echo-next rollout
   pushes `registry.digitalocean.com/dbr-cr/dembrane-web-*:<sha>` for every commit on main) and
   `global.imageTag` in `values-prod.yaml` names it, so the cluster needs nothing more.
   The release itself comes after step 8, once v3 serves production: `70-deploy-prod` posts
   "is live on prod" in the team channel, comments "Released in" on every pull request since
   the last release, publishes the GitHub Release and tells sam. A tag push alone runs checks
   only (the repository variable `PROD_DEPLOY_ON_TAG` is unset on purpose), so start the job by
   hand and approve it in the `prod` environment. It finds the image tag already set and
   commits nothing:
   ```sh
   git tag v3.0.0 fa8503af31b46c8e80f0251c6269dd2a3a028378 && git push origin v3.0.0
   gh workflow run platform.yml -R Dembrane/echo --ref main -f target=prod -f tag=v3.0.0
   ```
2. **Database login and secrets.** Done on 2026-10-11: the database user `echo_app`
   (`doctl databases user create <cluster id> echo_app`), the namespace `dembrane-web-prod`, and
   both sealed secrets, committed here and applied. `secrets/dembrane-web-prod-secrets.keys.md`
   says where each value comes from and how to build the secret again. Check:
   ```sh
   kubectl -n dembrane-web-prod get secret dembrane-web-prod-secrets do-registry-secret
   ```
   `S3_ACCESS_KEY` and `S3_SECRET_KEY` are the Spaces key `v3-prod-uploads`, which reaches only
   `dbr-echo-prod-uploads`; the old stack's key reaches every bucket in the account, the
   backups and the Terraform state among them, and stays out of v3.
   `GCP_SA_JSON` is the old stack's key and `LLM_VERTEX_PROJECT` its project, `dembrane-echo`:
   the three models v3 calls answer there on the EU host. The embedding model is not checked.
   Prove the pull secret before the window, once step 1 has pushed the images. The image has no
   shell, so the pod is not asked to run anything: the API starts without its settings and
   exits, which ends the pod as `Failed`. That end state with an image id means the pull
   worked. If the wait times out, the pod shows `ErrImagePull` or `ImagePullBackOff`: the
   secret is wrong.
   ```sh
   kubectl -n dembrane-web-prod run pull-test --restart=Never --image=registry.digitalocean.com/dbr-cr/dembrane-web-api:<sha> \
     --overrides='{"spec":{"imagePullSecrets":[{"name":"do-registry-secret"}]}}'
   kubectl -n dembrane-web-prod wait --for=jsonpath='{.status.phase}'=Failed pod/pull-test --timeout=120s
   kubectl -n dembrane-web-prod get pod pull-test \
     -o jsonpath='{.status.containerStatuses[0].imageID} {.status.containerStatuses[0].state.waiting.reason}'
   kubectl -n dembrane-web-prod delete pod pull-test
   ```
3. **Register the app, do not sync it.** `kubectl apply -f argo/dembrane-web-prod.yaml`.
   Automated sync is off: the app shows OutOfSync and nothing runs. The Cloudflare TTL of
   `dashboard`, `portal`, `api` and `directus` is 60 seconds.

## The window

4. **Stop the old stack.** Stop self-heal first, so the scale-down sticks, then wait for the
   workers to finish what they hold. The command runs in a worker pod, which reaches the private
   Valkey, and uses the app's own Python (the system one has no `redis`):
   ```sh
   argocd --core app set echo-prod --sync-policy none
   kubectl -n echo-prod exec deploy/echo-worker -- /code/server/.venv/bin/python -c 'import os, redis; r = redis.from_url(os.environ["REDIS_URL"]); print({q: r.llen("dramatiq:" + q) for q in ["network", "cpu", "ticks", "network.DQ", "cpu.DQ", "ticks.DQ"]})'
   ```
   At zero, or when waiting longer costs more than the leftovers, save what the queues still
   hold: a rollback would replay these against rows v3 may have changed, and the copy is what
   lets them be replayed by hand instead. Then scale everything to 0:
   ```sh
   kubectl -n echo-prod exec deploy/echo-worker -- /code/server/.venv/bin/python -c 'import os, json, redis; r = redis.from_url(os.environ["REDIS_URL"]); print(json.dumps({q: {k.decode(): v.decode() for k, v in r.hgetall(f"dramatiq:{q}.msgs").items()} for q in ["network", "cpu", "ticks", "network.DQ", "cpu.DQ", "ticks.DQ"]}))' > dramatiq-leftover.json
   kubectl -n echo-prod scale deployment --all --replicas=0
   kubectl -n echo-prod wait --for=delete pod --all --timeout=300s
   kubectl -n echo-prod get deploy,hpa
   ```
   Every Deployment shows 0/0 and stays there: an HPA does not scale a target at 0 replicas
   (its condition reads `ScalingDisabled`). The database and bucket are now written by nobody.
4b. **Back up the database.** The old stack is stopped, so this copy is the last state it wrote.
   `backup/db-backup-job.yaml` runs on the test cluster, reads production through one snapshot
   and uploads the dump, its table of contents, exact row counts and a hash to the private Space
   `dbr-echo-prod-backups` under `postgres/<stamp>/`. It leaves out the data of
   `processing_status`, `directus_revisions` and `lightrag_*` (35 of 43 GB; the tables are kept,
   empty); DigitalOcean's own daily backup still has them. The job needs its namespace and a
   secret first: the owner login on the direct port, the cluster's CA
   (`doctl databases get-ca <cluster id>`), and the Space key `prod-backups-writer`, which can
   touch only that bucket. Delete the namespace afterwards: it holds the database login.
   ```sh
   export KUBECONFIG=~/.kube/echo-next-only.yaml
   kubectl create namespace db-backup
   kubectl -n db-backup create secret generic backup \
     --from-literal=PROD_DATABASE_URL='<MIGRATION_DATABASE_URL>' \
     --from-literal=AWS_ACCESS_KEY_ID='<key id>' --from-literal=AWS_SECRET_ACCESS_KEY='<secret>' \
     --from-file=ca.crt=ca-certificate.crt
   kubectl apply -f backup/db-backup-job.yaml
   kubectl -n db-backup logs -f job/db-backup -c dump      # "PodInitializing" at first: run it again
   kubectl -n db-backup logs -f job/db-backup -c upload
   export KUBECONFIG=~/.kube/prod-argocd.yaml
   ```
   Go on only when the upload container has listed the four files. On 2026-10-08 the dump was
   2.1 GB and took about 8 minutes; `backup/db-restore-job.yaml` restored it into an empty
   database in about 4 minutes with every one of 95 tables at the dump's row count.
   To restore, give the same secret `RESTORE_DATABASE_URL` and `restore-ca.crt`, and set the
   folder in the job. The restore job has only run into an empty database: restore into a new
   database on the same cluster and point both stacks' URLs at it, never over `defaultdb`.
   DigitalOcean's point-in-time recovery (a fork of the cluster at a chosen minute) is the
   second line, and the only one that still holds the tables the dump leaves out.
5. **Sync v3 with the contract held.**
   ```sh
   argocd --core app get dembrane-web-prod --hard-refresh
   argocd --core app sync dembrane-web-prod
   kubectl -n dembrane-web-prod logs job/dembrane-web-migrate
   kubectl -n dembrane-web-prod logs job/dembrane-web-smoke
   ```
   The PreSync hook `dembrane-web-migrate` runs first with `MIGRATE_HOLD_CONTRACT=1`: expand
   migrations (the index builds on `processing_status` take a lock, which is why this waits for
   step 4), the DBOS schema, the identity copy from Directus, grants to `echo_app`. Its log
   says `adoptedBaseline: true` and `applied: 12`, then the users and accounts copied (every
   user with an email, whatever its status). The API, media, dashboard and portal roll out only
   if it succeeds; the PostSync hook `dembrane-web-smoke` then checks them in-cluster and ends
   with `passed`. All pending migrations run in one transaction, and the job is killed at
   `migrate.activeDeadlineSeconds`: an overrun rolls everything back and a retry starts from
   zero, so `values-prod.yaml` sets 3600.
6. **Start the worker.** Commit `worker.replicas: 2` in `values-prod.yaml`, refresh, sync. The
   smoke hook now also waits for a heartbeat from a worker of this release
   (`/ready/worker?release=`). The worker also runs the schedule the old scheduler ran, billing
   among it: with `APP_ENV=prod` the scheduled billing jobs may email customers and change
   their tier, and `billing.reconcile-seats` updates Mollie subscriptions. To hold the customer
   side for the first days, set `env.BILLING_CUSTOMER_JOBS: "off"` in `values-prod.yaml` in the
   same commit.
7. **Move the hostnames.** Delete the old ingress (self-heal is off, so it stays deleted; the
   ClusterIssuer `letsencrypt-prod` and the old certificate secret stay), then turn on v3's:
   ```sh
   kubectl -n echo-prod delete ingress echo-ingress
   ```
   Commit `ingress.enabled: true` and `ingress.legacyDirectus.enabled: true`, refresh, sync.
   `api.dembrane.com` and `directus.dembrane.com` already resolve to the cluster's load balancer
   (206.189.240.151), so their certificates issue within minutes:
   `kubectl -n dembrane-web-prod get ingress,certificate`.
8. **Smoke through the load balancer.**
   ```sh
   curl -s https://api.dembrane.com/health          # "release":"<sha>"
   curl -s https://api.dembrane.com/ready
   curl -s "https://api.dembrane.com/ready/worker?release=<sha>"
   for h in dashboard portal; do
     curl -sk --resolve $h.dembrane.com:443:206.189.240.151 https://$h.dembrane.com/runtime-config.js
   done
   curl -sI https://directus.dembrane.com/admin                        # 301 to the dashboard's sign-in
   curl -sI https://directus.dembrane.com/assets/<a known avatar id>   # 200 from the API
   ```
   Sign in with a staff account and a QA account, open a project, record a short conversation
   on the portal and watch it transcribe, play its audio (the storage key is new), ask a chat
   question (the smoke hook makes no model call), open a report.
9. **Dashboard and portal DNS.** In Cloudflare, replace the `dashboard` and `portal` CNAMEs to
   `cname.vercel-dns.com` with A records to 206.189.240.151, DNS only (not proxied). Their
   certificates issue by HTTP-01 once DNS answers; until then browsers see the ingress default
   certificate, so watch `kubectl -n dembrane-web-prod get certificate` and retest step 8
   without `--resolve`. cert-manager's self-check has been failing since step 7 and backs off to
   about 16 minutes between tries. To retry at once, delete the pending challenges (the order
   makes new ones), or the order itself if it has failed. Neither has been run:
   ```sh
   kubectl -n dembrane-web-prod delete challenges.acme.cert-manager.io --all
   kubectl -n dembrane-web-prod get order,certificate
   ```
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
    argocd --core app set dembrane-web-prod --revision main
    argocd --core app get dembrane-web-prod --hard-refresh
    argocd --core app diff dembrane-web-prod        # nothing but the revision
    ```
    Automated sync comes later still, after three releases synced by hand have gone well.
    Setting it starts a sync at once, on the revision Argo CD has cached, so refresh first:
    ```sh
    argocd --core app get dembrane-web-prod --hard-refresh
    argocd --core app set dembrane-web-prod --sync-policy automated --self-heal --auto-prune
    ```
    In Dembrane/echo set the repository variables `GITOPS_PROD_BRANCH=main` and
    `PROD_WAIT_FOR_ROLLOUT=true`, so each release bumps main and waits for the new release on
    `api.dembrane.com` before it announces.
    `GITOPS_PROD_BRANCH` also names the branch echo-next's tag is written to, so on the dev
    cluster point `dembrane-web-dummy` at main in the same step
    (`argocd --core app set dembrane-web-dummy --revision main`).
12. **Monitoring.** In `helm/monitoring/values-prod.yaml` replace the `directus` probe (it now
    redirects; probe `https://api.dembrane.com/ready` instead) and set `dashboards.namespace` to
    `dembrane-web-prod`.

## Rollback

Possible until the contract is released: the old stack's tables are all still there.

1. v3 off the hostnames and out of the queue, by hand:
   ```sh
   kubectl -n dembrane-web-prod delete ingress --all
   kubectl -n dembrane-web-prod scale deployment dembrane-web-worker --replicas=0
   ```
   Then commit `ingress.enabled: false`, `ingress.legacyDirectus.enabled: false` and
   `worker.replicas: 0` so the next sync does not put them back. A sync alone does not remove
   the ingresses (the app has no prune), and while they exist ingress-nginx keeps serving them
   and ignores the old stack's recreated `echo-ingress`.
2. Cloudflare: `dashboard` and `portal` back to CNAME `cname.vercel-dns.com`; re-add the domains
   in Vercel.
3. Old stack back. Setting the policy starts the sync by itself; a second `app sync` only
   answers "another operation is already in progress".
   ```sh
   argocd --core app set echo-prod --sync-policy automated --self-heal --auto-prune
   kubectl -n echo-prod get deploy,hpa,ingress
   curl -s -o /dev/null -w '%{http_code}\n' https://api.dembrane.com/api/health
   curl -s -o /dev/null -w '%{http_code}\n' https://directus.dembrane.com/server/health
   ```
   The sync recreates `echo-ingress` and sets every replica count from
   `helm/echo/values-prod.yaml` (API 6, Directus 2, workers 2 each); the HPAs take over from
   there. The API pods need a few minutes to start.

What v3 wrote in between stays in the shared tables and the old stack reads it. v3 also writes
new users and password hashes to `directus_users`, so sign-ups and password changes survive;
sessions and two-factor settings made on v3 do not. Messages saved in step 4 are replayed by
hand, after a look at what v3 did to their rows.

## Release the contract

Only when rollback is no longer wanted. Contract migrations drop tables only the old stack
read (`0012_contract_dead_features`: the old library, segments and LightRAG, about 21 GB).

1. Retire the old stack without losing the cluster-scoped objects its chart owns (the
   ClusterIssuer `letsencrypt-prod` every certificate here uses, and the PriorityClasses):
   `argocd --core app delete echo-prod --cascade=false`, then `kubectl delete namespace echo-prod`.
   The ClusterIssuer and PriorityClasses remain, unmanaged; move the ClusterIssuer into a chart
   that stays.
2. Archive what the contract drops, from Dembrane/echo:
   `DATABASE_URL=<MIGRATION_DATABASE_URL> dembrane/platform/packages/db/scripts/archive-tables.sh`.
   It needs `psql` and `pg_dump` 16, `PGSSLROOTCERT` set to the cluster's CA, and gcloud signed
   in with write access to the archive bucket; about 21 GB pass through the machine it runs on.
   It records the archive in `drizzle.contract_archive`.
3. Commit `migrate.holdContract: false`, refresh, sync. The migrate job applies every migration
   its history does not hold yet, so 0012 runs now although newer ones ran before it. Without
   its row in `drizzle.contract_archive` the job stops with `ContractArchiveMissing` before it
   applies anything. Its log says `applied: 1`. Later contract migrations run on deploy the
   same way, once their archive is recorded.
