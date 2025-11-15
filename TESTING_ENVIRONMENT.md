# Testing Environment

## Overview

The testing environment is a full replica of production/dev infrastructure used for automated testing and validation before deploying to production.

## Access

- **API**: https://api.echo-testing.dembrane.com
- **Directus**: https://directus.echo-testing.dembrane.com
- **Dashboard**: https://dashboard.echo-testing.dembrane.com
- **Portal**: https://portal.echo-testing.dembrane.com
- **API Docs**: https://api.echo-testing.dembrane.com/docs
- **ArgoCD**: Port-forward required (see below)

## Architecture

- **Cluster**: DO Kubernetes (2-4 nodes, s-4vcpu-8gb)
  - Cluster ID: `a4928776-f7e8-415d-ba00-e89a661b2a7a`
  - VPC: `117cb9fd-6fb3-4f10-94a0-62bf04943a80` (10.10.12.0/24)
  - LoadBalancer IP: `209.38.54.117`
- **Database**: Managed Postgres (db-s-1vcpu-1gb)
  - ID: `cda6545d-b8d7-4b39-b2ad-48e6cb2b97a4`
- **Cache**: Managed Redis (db-s-1vcpu-1gb)
  - ID: `d915397f-5ab2-4173-80be-3970644ed654`
- **Storage**: S3 bucket (`dbr-echo-testing-uploads`)
- **Deployment**: ArgoCD (auto-sync from main branch)

## Deployment Flow

1. Create PR to `testing` branch in echo repo
2. CI runs: linting, type checks, unit tests, build validation
3. On success: PR auto-merges to `testing` branch
4. On merge: CI builds images, tags as `<commit-sha>` and `testing`
5. CI updates `echo-gitops/helm/echo/values-testing.yaml` with new imageTag
6. ArgoCD detects change and deploys to testing cluster
7. Post-deployment: smoke tests run
8. Slack notification sent to #alerts-devops with results

## How to Deploy to Testing

### Option 1: Via PR (Recommended)

```bash
cd echo
git checkout testing
git pull
git checkout -b feature/my-feature
# Make changes...
git commit -am "feat: my feature"
git push -u origin feature/my-feature

# Create PR to testing branch on GitHub
# Tests will run automatically, PR will auto-merge on success
```

### Option 2: Direct Push (Use with caution)

```bash
cd echo
git checkout testing
git pull
# Make changes...
git commit -am "fix: urgent fix"
git push origin testing

# Deployment will trigger automatically
```

## Running Tests Locally

### Smoke Tests

```bash
cd echo/server

# Set test environment
export TEST_API_URL=https://api.echo-testing.dembrane.com
export TEST_DIRECTUS_URL=https://directus.echo-testing.dembrane.com

# Run smoke tests
pytest tests/smoke/ -v -m smoke
```

### Unit Tests

```bash
cd echo/server

# Run unit tests (what PR validation runs)
pytest tests/ -v -m "not integration and not slow and not smoke"
```

### Integration Tests

```bash
cd echo/server

# Run all integration tests (requires live services)
pytest tests/ -v -m integration
```

## Accessing the Cluster

### kubectl Access

```bash
# Get kubeconfig
doctl k8s c kubeconfig save dbr-echo-testing-k8s-cluster

# Set context
kubectl config use-context do-ams3-dbr-echo-testing-k8s-cluster

# Check pods
kubectl get pods -n echo-testing

# Check logs
kubectl logs -n echo-testing deployment/echo-api-server -f
```

### ArgoCD Access

```bash
# Port-forward ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Open browser: https://localhost:8080
# Username: admin
# Password: <from above>
```

## Debugging Failed Deployments

### Check ArgoCD Status

```bash
kubectl --context=do-ams3-dbr-echo-testing-k8s-cluster \
  get application -n argocd echo-testing -o yaml

# Force sync
kubectl --context=do-ams3-dbr-echo-testing-k8s-cluster \
  patch application echo-testing -n argocd \
  --type merge -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {}}}'
```

### Check Pod Status

```bash
kubectl get pods -n echo-testing
kubectl describe pod -n echo-testing <pod-name>
kubectl logs -n echo-testing <pod-name> --previous
```

### Check Events

```bash
kubectl get events -n echo-testing --sort-by='.lastTimestamp'
```

## Rollback Procedure

### Option 1: Git Revert (Recommended)

```bash
cd echo-gitops
git log  # Find the commit to revert
git revert <commit-sha>
git push origin main

# ArgoCD will auto-sync the previous version
```

### Option 2: Manual Image Rollback

```bash
cd echo-gitops

# Update values-testing.yaml with previous image tag
sed -i '' 's/imageTag: "abc123"/imageTag: "xyz789"/' helm/echo/values-testing.yaml

git add helm/echo/values-testing.yaml
git commit -m "Rollback testing to xyz789"
git push origin main
```

### Option 3: ArgoCD Rollback

```bash
# Via ArgoCD UI:
# 1. Go to echo-testing application
# 2. Click "History and rollback"
# 3. Select previous revision
# 4. Click "Rollback"
```

## Secrets Management

### Updating Secrets

```bash
cd echo-gitops

# 1. Create/update unsealed secret file
vim secrets/backend-secrets-testing.yaml

# 2. Seal the secret
kubeseal --context=do-ams3-dbr-echo-testing-k8s-cluster \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets \
  < secrets/backend-secrets-testing.yaml \
  > secrets/sealed-backend-secrets-testing.yaml

# 3. Apply sealed secret
kubectl --context=do-ams3-dbr-echo-testing-k8s-cluster \
  apply -f secrets/sealed-backend-secrets-testing.yaml

# 4. Delete unsealed file (IMPORTANT!)
rm secrets/backend-secrets-testing.yaml

# 5. Commit sealed secret
git add secrets/sealed-backend-secrets-testing.yaml
git commit -m "Update testing secrets"
git push origin main
```

## Monitoring

### Logs

```bash
# API Server logs
kubectl logs -n echo-testing deployment/echo-api-server -f

# Worker logs
kubectl logs -n echo-testing deployment/echo-worker -f

# Directus logs
kubectl logs -n echo-testing deployment/echo-directus -f
```

### Sentry

All errors are sent to Sentry with environment: `testing`

- Go to Sentry
- Filter by environment: testing
- View errors and performance

### Metrics

Use kubectl commands to check resource usage:

```bash
kubectl top nodes
kubectl top pods -n echo-testing
```

## Database Access

### Connect to Postgres

```bash
# Get connection details from Terraform output
cd infra
terraform workspace select testing
terraform output -json | jq .postgres_host

# Connect via psql (requires DO VPN or bastion)
psql "postgresql://<user>:<pass>@<host>:<port>/defaultdb?sslmode=require"
```

### Run Migrations

```bash
# SSH into API pod
kubectl exec -it -n echo-testing deployment/echo-api-server -- /bin/bash

# Run migrations
cd /app
alembic upgrade head
```

## Cost Optimization

To reduce costs when not actively using testing:

### Scale Down

```bash
# Scale to 0 replicas
kubectl scale deployment -n echo-testing --replicas=0 --all

# Keep databases running but downscale cluster
```

### Scale Up

```bash
# Scale back up
kubectl scale deployment -n echo-testing echo-api-server --replicas=1
kubectl scale deployment -n echo-testing echo-worker --replicas=1
kubectl scale deployment -n echo-testing echo-directus --replicas=1
```

## Troubleshooting

### DNS Issues

```bash
# Check DNS propagation
dig api.echo-testing.dembrane.com
dig directus.echo-testing.dembrane.com

# Check ingress
kubectl get ingress -n echo-testing
kubectl describe ingress -n echo-testing echo-ingress
```

### Certificate Issues

```bash
# Check cert-manager
kubectl get certificates -n echo-testing
kubectl describe certificate echo-testing-tls -n echo-testing

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f
```

### Image Pull Issues

```bash
# Check registry secret
kubectl get secret -n echo-testing do-registry-secret

# Recreate if needed (from Terraform output)
```

## Manual Testing Checklist

After deployment, manually verify:

- [ ] API health: `curl https://api.echo-testing.dembrane.com/health`
- [ ] Directus ping: `curl https://directus.echo-testing.dembrane.com/server/ping`
- [ ] API docs load: Open https://api.echo-testing.dembrane.com/docs
- [ ] Login to Directus: https://directus.echo-testing.dembrane.com
- [ ] Create a project via API
- [ ] Upload audio chunk
- [ ] Check Sentry for errors
- [ ] Check logs for errors

## Support

For issues or questions:
- Slack: #alerts-devops or #engineering
- Check GitHub Actions logs
- Check ArgoCD UI
- Check Sentry errors

## Related Documentation

- [Testing Stage Implementation](TESTING_STAGE_IMPLEMENTATION.md)
- [Deployment Rules](.cursor/rules/deploy-monitoring.mdc)
- [Main Infrastructure](infra/main.tf)

