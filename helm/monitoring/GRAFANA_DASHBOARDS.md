# Grafana Dashboards for Echo Monitoring

This document describes the pre-configured Grafana dashboards available in your monitoring setup and how to best use them for monitoring your Echo application.

## Available Dashboards

After deploying the monitoring stack using Helm, the following dashboards will be automatically available in Grafana:

### 1. Echo Application Dashboard

This dashboard is specifically designed for monitoring your Echo application with API, Directus, and Worker components. It includes:

- CPU and memory usage for API Server, Directus, and Worker components
- HTTP request rates and response times for API and Directus services
- Worker activity monitoring for background task processing
- Error logs from the Echo application
- Worker-specific logs

This dashboard automatically filters for pods and services in the `echo-dev` and `echo-prod` namespaces and allows switching between them.

### 2. Kubernetes Cluster Monitoring

This dashboard provides an overview of your Kubernetes cluster resources, including:

- Cluster-wide filesystem usage
- Node resource metrics
- Container statistics

### 3. Node Exporter Full Dashboard

Detailed infrastructure metrics for your cluster nodes:

- CPU usage across all nodes
- Memory utilization
- Disk space usage
- Network I/O

### 4. Nginx Ingress Controller Dashboard

Monitoring for your ingress traffic:

- HTTP request rates by ingress resource
- Response times
- Status code distribution

### 5. Loki Logs Dashboard

Centralized logging for your applications:

- Log volume metrics
- Real-time log viewing with filtering capabilities
- Error detection

## How to Use the Dashboards

1. Access Grafana through your ingress URL (e.g., `https://grafana.echo-next.dembrane.com`)
2. Log in with your admin credentials (from the `monitoring-secrets` SealedSecret)
3. Navigate to Dashboards > Browse to see all pre-configured dashboards
4. Select the Echo Application Dashboard for an immediate view of your Echo application's health

## Tips for Echo Application Monitoring

1. **Environment Selection**: Use the Environment dropdown at the top of the Echo Application Dashboard to switch between Development and Production views.

2. **Troubleshooting High Response Times**:
   - If you notice increased response times in the API or Directus components, check the corresponding CPU/Memory panels to determine if it's resource-related.
   - Use the Error Logs panel to see if there are any application errors correlating with performance issues.

3. **Worker Monitoring**:
   - Monitor worker CPU and memory usage to ensure background tasks are processing efficiently
   - The "Worker Activity" panel shows processing rates which can help identify if workers are actively processing tasks
   - Use the "Worker-Specific Logs" panel to troubleshoot worker-related issues

4. **Alerting**:
   - Consider setting up alerts for when API response times exceed acceptable thresholds.
   - Monitor memory usage and set alerts if usage approaches the limits configured in your Echo Helm values.
   - Set alerts for worker activity dropping below expected thresholds to detect stalled workers.

5. **Custom Queries**:
   - For advanced metrics, you can create custom panels using these base queries:
     - API Server pods: `{namespace=~"echo-.*", pod=~"echo-api.*"}`
     - Directus pods: `{namespace=~"echo-.*", pod=~"echo-directus.*"}`
     - Worker pods: `{namespace=~"echo-.*", pod=~"echo-worker.*"}`
     - Ingress metrics: `{ingress="echo-ingress"}`

## Dashboard Maintenance

These dashboards are provisioned automatically through ConfigMaps in the Helm chart. To make changes:

1. Update the dashboard JSON in `helm/monitoring/templates/configmap-grafana-dashboards.yaml`
2. Upgrade the Helm release with:
   ```bash
   helm upgrade --install monitoring ./helm/monitoring --namespace monitoring
   ```
   
3. Or commit the changes to your Git repository if using ArgoCD, which will automatically sync the changes. 