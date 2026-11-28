# dembrane-web-eu-secrets

The Secret every dembrane v3 unit in namespace `dembrane-web-prod` of the EU cluster reads
(helm/dembrane-web, values-eu-prod.yaml). No values are in this repository. It is sealed with
the EU cluster's own Sealed Secrets key as `secrets/sealed-dembrane-web-eu-secrets.yaml`
(not made yet); a secret sealed for the DigitalOcean cluster cannot be opened here.

Everything below is created new for the EU. No value is shared with production.

## Required

| Key | Read by | Value |
|---|---|---|
| `DATABASE_URL` | api, worker | Scaleway Managed PostgreSQL, **direct** connection (not a pooler: queues use LISTEN/NOTIFY and session advisory locks), as the runtime login `echo_app`, over the private network, ending in `?sslmode=require`. |
| `MIGRATION_DATABASE_URL` | migrate | Same host and database, as the owner login with DDL rights. |
| `DATABASE_CA_CERT` | api, worker, migrate | The database's CA certificate (PEM), mounted as a file and trusted through `NODE_EXTRA_CA_CERTS`. |
| `AUTH_SECRET` | api | New: `openssl rand -base64 48`. |
| `INVITE_HASH_SECRET` | api | New: `openssl rand -base64 48`. No old invite links exist to keep. |
| `HTTP_PROXY_SECRET` | api, dashboard, portal | New: `openssl rand -base64 48`. |
| `S3_ACCESS_KEY` | api, worker | Scaleway IAM access key limited to the one bucket. Becomes `FILES_S3_ACCESS_KEY_ID` and `STORAGE_S3_KEY`. |
| `S3_SECRET_KEY` | api, worker | Its secret key. |
| `LLM_API_KEY` | api, worker | Scaleway Generative APIs key (`api.scaleway.ai`). Pending the echo change. |
| `SCALEWAY_MAIL_SECRET_KEY` | api, worker | Scaleway key for Transactional Email. Pending the echo change. |
| `GCP_SA_JSON_EU` | api, worker | A service account key (JSON) of Google Cloud project `dembrane-echo` with `roles/aiplatform.user` and nothing else, for Vertex AI. Mounted as a file (`GOOGLE_APPLICATION_CREDENTIALS`). New for the EU: never the DigitalOcean `GCP_SA_JSON`. See below. |

## The Vertex key (`GCP_SA_JSON_EU`)

Google is a second provider here, for the accounts staff enable it for; Scaleway stays the
default (`LLM_PROVIDERS` in values-eu-prod.yaml). The key is created and added by Sameer:

1. In Google Cloud project `dembrane-echo`, create a service account for the EU (for example
   `echo-eu-vertex`) and grant it `roles/aiplatform.user` only.
2. Create a JSON key for it. It is the only copy: do not put it in a chat, a file in this
   repository or the DigitalOcean secret.
3. Add the whole JSON as key `GCP_SA_JSON_EU` of the EU Secret and seal it for the EU
   cluster (`secrets/sealed-dembrane-web-eu-secrets.yaml`).

The deploy must not happen before the key exists in the cluster's Secret: the key is mounted as
a file, and a pod whose mounted key is missing does not start (api and worker both). Merge the
change to prod-v3 only after the sealed Secret is applied.

## Not in this Secret (on purpose)

`GCP_SA_JSON` (the DigitalOcean Vertex key; the EU has its own, above),
`AUTH_GOOGLE_CLIENT_ID`, `AUTH_GOOGLE_CLIENT_SECRET`, `SENDGRID_API_KEY`, `MOLLIE_API_KEY`, `ECHO_SUPPORT_WEBHOOK_TOKEN`, `SITE_API_TOKEN`, `ACCOUNTS_SLACK_WEBHOOK_URL`,
`ACCOUNTS_EVENTS_SECRET`, `SAM_INBOX_SECRET`, `AGENT_CLIENT_SECRET_KEY`. The chart reads none of
them for the EU (`optionalSecretKeys` in values-eu-prod.yaml).

## The registry pull secret

`scw-registry-secret` (`kubernetes.io/dockerconfigjson`) in `dembrane-web-prod`: server
`rg.nl-ams.scw.cloud`, user `nologin`, password a Scaleway secret key with read access to the
registry namespace.

## Monitoring secrets (namespace `monitoring`)

| Secret | Keys |
|---|---|
| `monitoring-secrets` | `grafana-admin-password`. `slack-webhook-url` is not needed while alerts go nowhere. |
| `grafana-obs-db` | `OBS_PROD_DB_HOST` (host:port), `OBS_PROD_DB_NAME`, `OBS_PROD_DB_USER`, `OBS_PROD_DB_PASSWORD`: the read-only login of `helm/monitoring/sql/grafana-obs-role.sql` on the EU database. |
