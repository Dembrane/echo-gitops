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

## Default Dashboards

Some recommended dashboards to import:
- Kubernetes Cluster Monitoring (ID: 15661)
- Node Exporter Full (ID: 1860)
- Nginx Ingress Controller (ID: 9614)
- Loki Logs (ID: 12019)
- DigitalOcean Kubernetes Service (ID: 11545)

To import a dashboard:
1. Go to Dashboards → Import
2. Enter the dashboard ID
3. Select your Prometheus data source
4. Click Import

## Alerts

Alert rules are defined in the Prometheus configuration. Alerts are shown in Prometheus.

To customize alert rules, edit `helm/monitoring/templates/configmap-prometheus.yaml`.

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