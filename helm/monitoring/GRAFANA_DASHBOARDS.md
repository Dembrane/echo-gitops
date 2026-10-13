# Grafana Dashboards for Echo Monitoring

This document describes the pre-configured Grafana dashboards available in your monitoring setup and how to best use them for monitoring your Echo application.

## Available Dashboards

After deploying the monitoring stack using Helm, the following dashboards will be automatically available in Grafana:

### 1. dembrane v3 dashboards

The dashboards that follow the v3 stack live as JSON files in `dashboards/`:

- **dembrane v3: overview**: is it up, where does it hurt, is it scaling (ingress, pods, nodes, and API latency by route group from the API's own request log, live streams left out).
- **dembrane v3: worker and jobs**: the worker's queues and jobs, from its log lines.
- **dembrane v3: product**: who is recording now; conversations, hours, chunks, reports, chats, assistant runs and pipeline steps per Amsterdam day, today against yesterday.
- **dembrane v3: AI**: model calls, latency, context size, errors, refusals, retries and an estimated cost, per operation and per day. Its first row compares every environment and does not follow the Environment dropdown: production, staging and sam from their own record of calls, the previews from Google's count of tokens.
- **dembrane: sam**: sam, the team's agent in Slack: how long people wait for a first answer, what a request costs, how many model calls a request takes, and what fails again and again. Its model calls also show in the AI dashboard, as the environment `sam`.
- **dembrane v3: staging and previews**: the environments on Google Cloud Run: requests, 5xx, response time, containers, the worker's queues, the database, AI usage (Google's count of tokens and calls for the project, and the app's newest model calls with the pull request on previews) and the app's own log lines at warning level or above.
- **dembrane v3: what is going wrong**: only failures, in plain words, of every layer and environment on one page: the state right now (alerts firing, workers, public checks, queues), counts of what went wrong in the selected time, then a row each for stuck or failing work, application errors, the cluster, staging and the previews, and sam. It reads the same sources as the dashboards above and links to them for the detail.

The product and AI dashboards read each environment's Postgres through the `obs` views (counts, durations and sizes only) as a read-only role (`sql/grafana-obs-role.sql`). Their "Environment" dropdown switches between the data sources named `dembrane <env>`, so production and staging share one dashboard; each data source's address and login come from the secret `grafana-obs-db`.

The staging and previews dashboard reads Google Cloud Monitoring and Cloud Logging through two read-only data sources per environment, `google metrics <env>` and `google logs <env>` (uids `gcm-<env>` and `gcl-<env>`, which its "Environment" dropdown builds). The login and each environment's Google project come from the secret `grafana-google-sources`, so no file names a project: the dashboard reads the project from the metrics themselves, in a hidden variable. That variable leans on two behaviours of Grafana 10.0 (a metric query without a project uses the data source's default project, and the query needs a project field that is not empty before it runs), so open this dashboard first after a Grafana upgrade. For a free log search use Explore with a `google logs` data source and press "Run query"; the editor fills in the project.

The Cloud Logging data source is a plugin, pinned in `values.yaml` to the last version for Grafana 10. An init container installs it into Grafana's volume once and always succeeds: without the plugin the log panels are empty and everything else works.

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

### 6. dembrane v3: overview

One screen for the person on watch: is dembrane v3 up, where does it hurt, is it scaling.

- Top row: the public checks, 5xx share, p95 latency, pods not ready, restarts and OOM kills in the last hour
- Traffic: requests per second by host and by status class, p95 latency by host
- Workloads: one row per deployment (ready pods against the autoscaler's minimum and maximum, CPU against request and limit, memory against limit) and ready pods over time
- Worker jobs: jobs waiting, running and failed, and jobs finished per minute
- Nodes: ready nodes per pool, CPU and memory use per node
- API routes (closed by default): requests, 5xx answers and p95 latency per route, from the API's request log

### 7. dembrane v3: worker and jobs

The worker's queues and jobs (DBOS) and the log lines that need attention.

- Queues: jobs waiting, running, failed and deferred, now and per queue over time, the age of the oldest waiting job and the scheduler heartbeat
- Jobs: jobs finished per minute by area, failed attempts by job, and a table per job (runs, failed attempts, slowest run, last run)
- Logs: error and warning lines per service, with the lines below
- Worker pods: CPU against request and limit, memory against limit
- Last release: the result of the migrate and smoke jobs and what they wrote

### How the v3 dashboards get their data

- The `Namespace` dropdown offers the namespace from `dashboards.namespace` and every `dembrane-web-*` namespace that runs pods. No query names a namespace itself.
- Traffic comes from ingress-nginx, pods and autoscalers from kube-state-metrics, CPU and memory from cAdvisor, nodes from node-exporter, the public checks from the blackbox exporter.
- Queues and jobs come from the worker's log through Loki: the worker logs one `queue.depth` line per queue every minute and one `job done` or `job failed` line per attempt. Loki reads at most 13 hours in one query, so these panels show an error on a longer time range.
- A colour or a dashed line marks a real limit only: a container limit, an autoscaler maximum, or a threshold of an alert rule in `templates/configmap-prometheus.yaml`.

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

1. Update the dashboard JSON in `helm/monitoring/templates/configmap-grafana-dashboards.yaml`. The two dembrane v3 dashboards are JSON files in `helm/monitoring/dashboards/`; `__NAMESPACE__` in them is replaced by `dashboards.namespace`. A new file there also needs a key in that ConfigMap and an item in `templates/deployment-grafana.yaml`.
2. Upgrade the Helm release with:
   ```bash
   helm upgrade --install monitoring ./helm/monitoring --namespace monitoring
   ```
   
3. Or commit the changes to your Git repository if using ArgoCD, which will automatically sync the changes. 