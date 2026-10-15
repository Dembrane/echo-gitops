# dembrane-web-eu-secrets

The Secret every dembrane v3 unit in namespace `dembrane-web-prod` of the EU cluster reads
(helm/dembrane-web, values-eu-prod.yaml). No values are in this repository. It is sealed with
the EU cluster's own Sealed Secrets key as `secrets/sealed-dembrane-web-eu-secrets.yaml`
(not made yet); a secret sealed for the DigitalOcean cluster cannot be opened here.

Everything below is created new for the EU. No value is shared with production.

## Required

| Key | Read by | Value |
|---|---|---|
| `DATABASE_URL` | api, worker | Scaleway Managed PostgreSQL, **direct** connection (not a pooler: queues use LISTEN/NOTIFY and session advisory locks), as the runtime login `echo_app`, ending in `?sslmode=verify-full`. |
| `MIGRATION_DATABASE_URL` | migrate | Same host and database, as the owner login with DDL rights. |
| `DATABASE_CA_CERT` | api, worker, migrate | The database's CA certificate (PEM), mounted as a file and trusted through `NODE_EXTRA_CA_CERTS`. |
| `AUTH_SECRET` | api | New: `openssl rand -base64 48`. |
| `INVITE_HASH_SECRET` | api | New: `openssl rand -base64 48`. No old invite links exist to keep. |
| `HTTP_PROXY_SECRET` | api, dashboard, portal | New: `openssl rand -base64 48`. |
| `S3_ACCESS_KEY` | api, worker | Scaleway IAM access key limited to the one bucket. Becomes `FILES_S3_ACCESS_KEY_ID` and `STORAGE_S3_KEY`. |
| `S3_SECRET_KEY` | api, worker | Its secret key. |
| `LLM_API_KEY` | api, worker | Scaleway Generative APIs key (`api.scaleway.ai`). Pending the echo change. |
| `SCALEWAY_MAIL_SECRET_KEY` | api, worker | Scaleway key for Transactional Email. Pending the echo change. |

## Not in this Secret (on purpose)

`GCP_SA_JSON`, `AUTH_GOOGLE_CLIENT_ID`, `AUTH_GOOGLE_CLIENT_SECRET`, `SENDGRID_API_KEY`,
`MOLLIE_API_KEY`, `ECHO_SUPPORT_WEBHOOK_TOKEN`, `SITE_API_TOKEN`, `ACCOUNTS_SLACK_WEBHOOK_URL`,
`ACCOUNTS_EVENTS_SECRET`, `SAM_INBOX_SECRET`, `AGENT_CLIENT_SECRET_KEY`. The chart reads none of
them for the EU (`optionalSecretKeys` in values-eu-prod.yaml).

## The registry pull secret

`scw-registry-secret` (`kubernetes.io/dockerconfigjson`) in `dembrane-web-prod`: server
`rg.fr-par.scw.cloud`, user `nologin`, password a Scaleway secret key with read access to the
registry namespace.

## Monitoring secrets (namespace `monitoring`)

| Secret | Keys |
|---|---|
| `monitoring-secrets` | `grafana-admin-password`. `slack-webhook-url` is not needed while alerts go nowhere. |
| `grafana-obs-db` | `OBS_PROD_DB_HOST` (host:port), `OBS_PROD_DB_NAME`, `OBS_PROD_DB_USER`, `OBS_PROD_DB_PASSWORD`: the read-only login of `helm/monitoring/sql/grafana-obs-role.sql` on the EU database. |
