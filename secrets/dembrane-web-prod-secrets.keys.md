# dembrane-web-prod-secrets

The Secret every dembrane v3 unit in namespace `dembrane-web-prod` reads (helm/dembrane-web).
It reaches the cluster as the SealedSecret `secrets/sealed-dembrane-web-prod-secrets.yaml`,
applied by hand like the others here. No values are in this repository; this file says where
each one comes from. "Old secret" means `echo-backend-secrets` in `echo-prod`
(`./secret-manager.sh prod get <KEY>` on a machine with the plaintext file).

## Required

The pods do not start without these.

| Key | Read by | Value |
|---|---|---|
| `DATABASE_URL` | api, worker | The DO managed Postgres **direct** connection (port 25060, not the pooler on 25061: DBOS and the live-stream hub use LISTEN/NOTIFY and session advisory locks), the same database the old stack uses, as the runtime login `echo_app`, ending in `?sslmode=verify-full`. `echo_app` is a new DO database user; the migrate job grants it data rights and nothing else. |
| `MIGRATION_DATABASE_URL` | migrate | Same host, port and database, as the login that **owns** the tables (the one Directus created them with, the user in the old secret's `DATABASE_URL`), ending in `?sslmode=verify-full`. It needs DDL rights: it alters tables and creates the `drizzle` and `dbos` schemas. |
| `DATABASE_CA_CERT` | api, worker, migrate | The DO database cluster's CA certificate (PEM, "Download CA certificate" on the cluster's page). Mounted as a file and trusted through `NODE_EXTRA_CA_CERTS`: DBOS's node-postgres treats `sslmode=require` as `verify-full` and rejects DO's private CA otherwise. |
| `AUTH_SECRET` | api | New: `openssl rand -base64 48`. Signs sessions; rotating it signs everyone out. Not the staging value. |
| `INVITE_HASH_SECRET` | api | Must equal the old secret's `DIRECTUS_SECRET`, or every invite link already sent stops working. It is also the fallback key for registered MCP clients' secrets. |
| `HTTP_PROXY_SECRET` | api, dashboard, portal | New: `openssl rand -base64 48`. Lets the API trust the caller address the web servers forward. |
| `S3_ACCESS_KEY` | api, worker | The Spaces key for `dbr-echo-prod-uploads`: the old secret's `S3_ACCESS_KEY`, or a new Spaces key limited to that bucket. Becomes `FILES_S3_ACCESS_KEY_ID` and `STORAGE_S3_KEY`. |
| `S3_SECRET_KEY` | api, worker | Its secret: the old secret's `S3_SECRET_KEY` or the new key's. Becomes `FILES_S3_SECRET_ACCESS_KEY` and `STORAGE_S3_SECRET`. |
| `GCP_SA_JSON` | api, worker | A JSON key for a service account in `dembrane-web-prod` with `roles/aiplatform.user` (Vertex AI on the EU endpoint). Mounted as a file for `GOOGLE_APPLICATION_CREDENTIALS`. If the key is from another project, change `LLM_VERTEX_PROJECT` in values-prod.yaml to match. |

## Optional

Each becomes an env var of the same name on the API and the worker. A missing key leaves the
feature off, as on staging.

| Key | Value |
|---|---|
| `AGENT_CLIENT_SECRET_KEY` | Leave unset: it falls back to `INVITE_HASH_SECRET`, which holds Directus's `SECRET`, the key the 7 registered MCP clients' secrets are encrypted under. |
| `AUTH_GOOGLE_CLIENT_ID` | The old secret's `AUTH_GOOGLE_CLIENT_ID`, once the OAuth client lists `https://api.dembrane.com/api/auth/callback/google` as a redirect URI. |
| `AUTH_GOOGLE_CLIENT_SECRET` | The old secret's `AUTH_GOOGLE_CLIENT_SECRET`. |
| `SENDGRID_API_KEY` | The old secret's `SENDGRID_API_KEY` (an EU subuser key; `SENDGRID_REGION` defaults to eu). Unset, no email is sent. |
| `MOLLIE_API_KEY` | The old secret's `MOLLIE_API_KEY` (`live_`). |
| `ECHO_SUPPORT_WEBHOOK_TOKEN` | The old secret's `ECHO_SUPPORT_WEBHOOK_TOKEN`; pairs with `SUPPORT_WEBHOOK_URL` in values-prod.yaml. |
| `SITE_API_TOKEN` | The token the public website sends for pricing configurations; unset falls back to `ECHO_SUPPORT_WEBHOOK_TOKEN`. |
| `ACCOUNTS_SLACK_WEBHOOK_URL` | The Slack incoming webhook for signatures and billing details, the value staging's Secret Manager holds for prod. |
| `ACCOUNTS_EVENTS_SECRET` | Signs account events to sam; set with `ACCOUNTS_EVENTS_URL` in values-prod.yaml or not at all. |

Old keys v3 does not read: `ASSEMBLYAI_*`, `DIRECTUS_ADMIN_*`, `DIRECTUS_EMAIL_*`, `LLM__*`,
`REDIS_URL`.

## The registry pull secret

The pods pull from `registry.digitalocean.com/dbr-cr` with `do-registry-secret`
(`kubernetes.io/dockerconfigjson`) in `dembrane-web-prod`. The old stack's copy lives in
`echo-prod` and is not shared across namespaces. Make a read-only one with
`doctl registry kubernetes-manifest --namespace dembrane-web-prod --name do-registry-secret`
and seal it the same way, as `secrets/sealed-do-registry-secret-web-prod.yaml`.

## Sealing

Nothing here is sealed yet. On a machine with kubeseal and the prod cluster context:

```sh
# 1. The plaintext file, ignored by git (secrets/.gitignore). One-line values from a KEY=value
#    file; the two file values (GCP_SA_JSON, DATABASE_CA_CERT) from disk.
kubectl create secret generic dembrane-web-prod-secrets -n dembrane-web-prod \
  --from-env-file=secrets-web-prod.txt \
  --from-file=GCP_SA_JSON=gcp-sa.json --from-file=DATABASE_CA_CERT=ca-certificate.crt \
  --dry-run=client -o yaml > secrets/dembrane-web-prod-secrets.yaml

# 2. Check the key list against this file, then seal and commit only the sealed file.
./secret-manager.sh web-prod list
./secret-manager.sh web-prod seal
```

`./secret-manager.sh web-prod update` and `batch` work on single-line values afterwards; the
two file values are replaced by rerunning step 1.
