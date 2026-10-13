# Echo Monitoring Stack

This Helm chart deploys a monitoring stack for the Echo platform including:

- Prometheus for metrics collection
- Grafana for visualization
- Loki for log aggregation (accessible only within the cluster)
- Promtail for log collection

## Prerequisites

- Kubernetes cluster with RBAC enabled
- Cert-manager installed for TLS certificates
- Nginx-ingress controller for ingress
- Sealed Secrets controller for secret management

## Deployment

The monitoring stack is deployed using ArgoCD. There are two environments:

### Development Environment

```bash
# Apply the ArgoCD application
kubectl apply -f argo/echo-monitoring-dev.yaml

# Create and apply sealed secrets
# First update the secrets file with real values:
nano secrets/monitoring-secrets-dev.yaml

# Then seal it:
kubeseal --context=do-ams3-dbr-echo-dev-k8s-cluster \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets \
  < secrets/monitoring-secrets-dev.yaml > secrets/sealed-monitoring-secrets-dev.yaml

# Apply the sealed secrets
kubectl apply -f secrets/sealed-monitoring-secrets-dev.yaml
```

### Production Environment

```bash
# Apply the ArgoCD application
kubectl apply -f argo/echo-monitoring-prod.yaml

# Create and apply sealed secrets
# First update the secrets file with real values:
nano secrets/monitoring-secrets-prod.yaml

# Then seal it:
kubeseal --context=do-ams3-dbr-echo-prod-k8s-cluster \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets \
  < secrets/monitoring-secrets-prod.yaml > secrets/sealed-monitoring-secrets-prod.yaml

# Apply the sealed secrets
kubectl apply -f secrets/sealed-monitoring-secrets-prod.yaml
```

## DNS Configuration

After the monitoring stack is deployed, you need to configure DNS records for the monitoring services:

### Development

```
grafana-echo-dev.echo-next.dembrane.com    → DigitalOcean Load Balancer IP
prometheus-echo-dev.echo-next.dembrane.com → DigitalOcean Load Balancer IP
```

### Production

```
grafana-echo-prod.dembrane.com    → DigitalOcean Load Balancer IP
prometheus-echo-prod.dembrane.com → DigitalOcean Load Balancer IP
```

To get the load balancer IP, run:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Accessing the Monitoring Stack

### Grafana

- URL (Development): https://grafana-echo-dev.echo-next.dembrane.com
- URL (Production): https://grafana-echo-prod.dembrane.com

Default login credentials:
- Username: admin
- Password: Defined in `monitoring-secrets-dev.yaml` or `monitoring-secrets-prod.yaml`

### Prometheus

- URL (Development): https://prometheus-echo-dev.echo-next.dembrane.com
- URL (Production): https://prometheus-echo-prod.dembrane.com

## Visualizing Data in Grafana

1. Log in to Grafana
2. Go to Configuration → Data Sources
3. Make sure Prometheus is configured with:
   - URL: http://prometheus:9090
4. Add Loki as a data source with:
   - URL: http://loki:3100

## Dashboards

### Customer activity

`dembrane v3: customers` (`v3-customers`) uses production only. Its default
audience hides dembrane's own organisation; the selector can include it again.
Other demo/trial organisations may still appear. These are observed product
actions, not paid-account counts or an inferred churn score.

Before deploying its JSON, apply `sql/customer-views.sql` as the existing
observability/migration owner. It adds seven `obs.customer_*` views and grants
only SELECT on them to `grafana_obs`. Do not grant access to the underlying
product tables. No customer rows, transcripts, prompts or contact fields change.
Emails embedded in display names are masked. The fixture function in
`sql/test-customer-views.py` tests the SQL against session-local temporary
tables, never real product rows.

Fresh audio uses three-minute client AND server timestamps; visitor telemetry
uses expiry and a 90-second freshness guard. Neither unfinished conversations
nor long-lived recording indexes prove a person is still recording. Pageviews
and idle dashboard tabs are not measured. Samples, clones and deleted content
are excluded. Attribution gaps and source failures remain visible.

Daily activity covers up to 200 days of retained source rows; first-use
milestones read the first retained core action, not signup or first-ever use
of deleted content. Momentum compares equal rolling seven-day windows. Views
are kept here with the dashboard, independently of the older aggregate views.

### Admin password rotation

Grafana's admin password lives in its database as well as the Kubernetes source.
Changing `GF_SECURITY_ADMIN_PASSWORD` or its Secret alone does not rotate an
existing database login. Update the admin password through the authenticated
Grafana Admin API, update the one encrypted password key in the existing
SealedSecret, verify reconciliation, and test new login plus old-password rejection.
Keep all other secret keys unchanged, including the production Slack webhook.
Commit only sealed ciphertext. Do not put plaintext in command arguments,
shell history, logs, screenshots or chat.

An authorised operator on a Mac can copy the live credential without printing it:

```sh
ssh sam2k-predator-ph315-52 \
  'kubectl --context do-ams3-dbr-echo-prod-k8s-cluster -n monitoring get secret monitoring-secrets -o jsonpath="{.data.grafana-admin-password}" | base64 -d' \
  | pbcopy
```

Paste into Grafana or a password manager, then clear the clipboard:
`printf '' | pbcopy`. This requires SSH and Kubernetes secret-read access.

Production retains Loki logs and Prometheus metrics for 200 days. Loki accepts
25-hour queries so a 24-hour dashboard also fits its small lookback windows.
Long retention does not restore history deleted by the previous seven-day policy.
Development retains its existing seven-day and 13-hour defaults.

Production starts with 40 GiB each for `loki-data` and `prometheus-data`.
This is a starting capacity, not a guarantee that every growth rate fits 200 days.
Do not set a Prometheus size-retention cap that silently deletes history early.
Expand PVCs through `storage` in `values-prod.yaml`, never delete/recreate them.
The storage class supports expansion; verify claim capacity and filesystem size
after Argo sync. Volume expansion cannot be rolled back by shrinking the claim.

PVC free-space metrics come from kubelet through the Kubernetes API proxy.
`#alerts-prod` receives notices below 20% free, a seven-day growth forecast,
and missing-capacity signals. Below 5% free is critical, with the existing
channel tag and repeat cadence. Critical disk alerts suppress their earlier
notices for the same PVC. The rules cover logs, metrics and Grafana's state disk.
History is not a backup; these volumes are still single copies.

The dashboards are JSON files in `dashboards/`, loaded from this chart; `GRAFANA_DASHBOARDS.md`
says what each one shows. A dashboard made by hand in Grafana lives only in Grafana's own
volume: add its file here to keep it with the others.

## Alerts

The application rules are `rules/app-alerts.yml`, the routing and the Slack message are
`alertmanager/alertmanager.yml`; both are plain files, so their own tools check them:

```
promtool check rules helm/monitoring/rules/app-alerts.yml
promtool test rules helm/monitoring/rules/app-alerts.test.yml
amtool check-config helm/monitoring/alertmanager/alertmanager.yml
```

Every alert carries three sentences: `summary` (what happened), `impact` (who feels it) and
`action` (the first step). The Slack message is made of those three. A `critical` alert tags
the channel and repeats every 30 minutes while it lasts, a `notice` is posted once, a
`warning` is only counted in the weekly digest.

The queue alerts read `dembrane_queue_*`, which promtail makes from the worker's
`queue.depth` log lines (`templates/configmap-promtail.yaml`). Try a change to those stages
with the same promtail image and `-dry-run` before it is merged: a stage promtail cannot
parse stops it from starting.

Prometheus and Alertmanager mount their files by subPath and promtail reads its config at
start, so after a sync: `kubectl -n monitoring rollout restart ds/promtail deploy/prometheus
deploy/alertmanager`.

## Handling Secrets

The monitoring stack uses two types of secrets:

1. **Basic Auth for Ingress**: Protects access to Prometheus and Grafana UI
2. **Grafana Admin Password**: Sets the admin password for Grafana

### Setting Up Basic Auth

For development, basic auth credentials are defined in `values.yaml`. For production:

1. Generate a proper htpasswd encoded string:
   ```bash
   htpasswd -nb admin your-secure-password
   ```

2. Update the credentials in your `monitoring-secrets-prod.yaml`:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: monitoring-secrets
     namespace: monitoring
   type: Opaque
   stringData:
     basic-auth-username: "admin"
     basic-auth-password: "your-secure-password"
     grafana-admin-password: "your-grafana-password"
   ```

3. Encrypt with sealed-secrets:
   ```bash
   kubeseal --context=do-ams3-dbr-echo-prod-k8s-cluster \
     --controller-namespace=kube-system \
     --controller-name=sealed-secrets \
     < secrets/monitoring-secrets-prod.yaml > secrets/sealed-monitoring-secrets-prod.yaml
   ```

4. Apply the sealed secret:
   ```bash
   kubectl apply -f secrets/sealed-monitoring-secrets-prod.yaml
   ```
