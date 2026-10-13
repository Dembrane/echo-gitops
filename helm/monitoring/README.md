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

The dashboards are JSON files in `dashboards/`, loaded from this chart; `GRAFANA_DASHBOARDS.md`
says what each one shows. A dashboard made by hand in Grafana lives only in Grafana's own
volume: add its file here to keep it with the others.

## Alerts

The application rules are `rules/app-alerts.yml` and the routing is
`alertmanager/alertmanager.yml`; both are plain files, so their own tools check them:

```
promtool check rules helm/monitoring/rules/app-alerts.yml
promtool test rules helm/monitoring/rules/app-alerts.test.yml
amtool check-config helm/monitoring/alertmanager/alertmanager.yml
```

Every alert carries a `title` (the thing and what happened to it), three sentences:
`summary` (what happened), `impact` (who feels it) and `action` (the first step), and a
`link`. The Slack message is made of those. A `critical` alert tags the channel and is sent
again every 30 minutes while it lasts, a `notice` tags nobody and is sent again every 12
hours, a `warning` is only counted in the weekly digest.

Alertmanager sends each alert to sam, the team's agent, which keeps one Slack message per
alert: it posts the message, edits it when the alert changes or is over, and replies in its
thread while it lasts. Alertmanager only says what fires; how the message looks is sam's.

### The token for alerts

Alertmanager shows sam a token with every alert. It reads it from the file
`sam-alerts-token` of `monitoring-secrets`, on every send, so a new value needs no restart.
The value comes from the secret store of sam's project (`ALERTMANAGER_WEBHOOK_TOKEN`). To
add or replace that one key without the other values of the secret:

```bash
gcloud secrets versions access latest --secret=ALERTMANAGER_WEBHOOK_TOKEN --project=<sam's project> \
  | kubectl create secret generic monitoring-secrets --namespace monitoring \
      --dry-run=client --from-file=sam-alerts-token=/dev/stdin -o json \
  | kubeseal --context=do-ams3-dbr-echo-prod-k8s-cluster \
      --controller-namespace=kube-system --controller-name=sealed-secrets \
      --merge-into secrets/sealed-monitoring-secrets-prod.yaml

kubectl --context=do-ams3-dbr-echo-prod-k8s-cluster apply -f secrets/sealed-monitoring-secrets-prod.yaml

# The key is there (this prints its name, never its value):
kubectl --context=do-ams3-dbr-echo-prod-k8s-cluster -n monitoring get secret monitoring-secrets \
  -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}'
```

Commit the changed `secrets/sealed-monitoring-secrets-prod.yaml`. The key has to be in the
cluster before the routes in `alertmanager/alertmanager.yml` point at `sam-prod`: without the
file Alertmanager cannot send, and no alert is posted.

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