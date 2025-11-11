# Testing Stage Implementation Plan

## Overview

This document outlines the complete implementation plan for adding a testing stage to the Echo infrastructure. The testing environment will:

1. Deploy from the `testing` branch in the echo repository
2. Run automated tests (unit, smoke, E2E)
3. Notify team via Slack
4. Provide a stable environment for pre-production validation

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  GitHub: echo repository                                            │
├─────────────────────────────────────────────────────────────────────┤
│  1. Create PR → testing branch                                      │
│  2. Run: linting, type check, unit tests, build images             │
│  3. Auto-merge on success                                           │
│                                                                      │
│  4. On merge to testing:                                            │
│     a. Build & push images → DO Registry                           │
│        Tags: <commit-sha>, testing (moving tag)                    │
│     b. Update gitops repo: values-testing.yaml with new imageTag   │
│     c. Commit & push to echo-gitops                                │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  GitHub: echo-gitops repository                                     │
├─────────────────────────────────────────────────────────────────────┤
│  5. ArgoCD detects new imageTag in values-testing.yaml             │
│  6. Auto-syncs to testing cluster                                  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  DigitalOcean: Testing Cluster                                     │
├─────────────────────────────────────────────────────────────────────┤
│  7. New deployment rolls out                                       │
│  8. Post-deployment: Run smoke tests (10min timeout)               │
│  9. Post-deployment: Run Playwright E2E tests                      │
│  10. Send Slack notification (#alerts-devops)                      │
│      ✅ Success: Deployment + test results                         │
│      ❌ Failure: Error + rollback instructions                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Infrastructure Setup (Days 1-2)

**Goal**: Create testing cluster, databases, and all required infrastructure.

### 1.1 Update Terraform Configuration

**File**: `infra/main.tf`

**Changes needed**:

1. Update locals to support `testing` environment:

```hcl
locals {
  # If workspace is default, use "dev" as the environment name
  # If workspace is testing, use "testing"
  # Otherwise use workspace name (prod)
  env = terraform.workspace == "default" ? "dev" : (terraform.workspace == "testing" ? "testing" : terraform.workspace)
}
```

2. Update VPC IP range to include testing:

```hcl
resource "digitalocean_vpc" "echo_vpc" {
  name     = "echo-${local.env}-vpc"
  region   = var.do_region
  ip_range = local.env == "prod" ? "10.10.10.0/24" : (local.env == "testing" ? "10.10.12.0/24" : "10.10.11.0/24")
}
```

3. Update Kubernetes cluster node configuration for testing:

```hcl
resource "digitalocean_kubernetes_cluster" "doks" {
  name     = "dbr-echo-${local.env}-k8s-cluster"
  region   = var.do_region
  vpc_uuid = digitalocean_vpc.echo_vpc.id
  version  = "1.32.2-do.0"
  node_pool {
    name       = "default-pool"
    size       = "s-4vcpu-8gb"
    auto_scale = true
    min_nodes  = local.env == "prod" ? 2 : (local.env == "testing" ? 2 : 1)
    max_nodes  = local.env == "prod" ? 6 : (local.env == "testing" ? 4 : 3)
    tags       = ["dbr-echo", local.env]
  }
}
```

4. Update database sizes for testing (same as dev):

```hcl
resource "digitalocean_database_cluster" "postgres" {
  # ... existing config ...
  size = local.env == "prod" ? "db-s-2vcpu-4gb" : "db-s-1vcpu-1gb"
  # ... rest of config ...
}

resource "digitalocean_database_cluster" "redis" {
  # ... existing config ...
  size = local.env == "prod" ? "db-s-2vcpu-4gb" : "db-s-1vcpu-1gb"
  # ... rest of config ...
}
```

### 1.2 Deploy Testing Infrastructure

**Commands to run**:

```bash
cd /Users/dattran/Development/echo-gitops/infra

# Select or create testing workspace
terraform workspace select -or-create testing

# Review the plan
terraform plan

# Apply the infrastructure
terraform apply

# This will create:
# - VPC: echo-testing-vpc (10.10.12.0/24)
# - K8s Cluster: dbr-echo-testing-k8s-cluster (2-4 nodes, s-4vcpu-8gb)
# - Postgres: dbr-echo-testing-postgres (db-s-1vcpu-1gb)
# - Redis: dbr-echo-testing-redis (db-s-1vcpu-1gb)
# - S3 Bucket: dbr-echo-testing-uploads
# - All helm releases: argocd, sealed-secrets, ingress-nginx, cert-manager, metrics-server
```

**Expected output**: 
- ✅ New kubernetes cluster created: `dbr-echo-testing-k8s-cluster`
- ✅ Cluster ID: `a4928776-f7e8-415d-ba00-e89a661b2a7a`
- ✅ VPC: `117cb9fd-6fb3-4f10-94a0-62bf04943a80` (10.10.12.0/24)
- ✅ Nodes: 2x s-4vcpu-8gb
- ✅ Get kubeconfig: `doctl k8s c kubeconfig save dbr-echo-testing-k8s-cluster`
- ✅ Verify context: `kubectl config get-contexts`

### 1.3 DNS Configuration

**LoadBalancer IP**: `209.38.54.117`

**Required DNS Records**:

Add the following records to your DNS provider:

```
# Backend (point to LoadBalancer)
A    api.echo-testing.dembrane.com        → 209.38.54.117
A    directus.echo-testing.dembrane.com   → 209.38.54.117

# Frontend (point to Vercel)
CNAME dashboard.echo-testing.dembrane.com → cname.vercel-dns.com
CNAME portal.echo-testing.dembrane.com    → cname.vercel-dns.com
```

**Vercel Projects Created**:
- `echo-dashboard-testing` (ID: prj_VEa4r4YxNBPqUzOsswUuRgGANnEn)
- `echo-portal-testing` (ID: prj_5CRQIJ2PL1ggUZijPZblieEGz03Z)

**DNS Checklist**:
- [x] `api.echo-testing.dembrane.com` → LoadBalancer IP: **209.38.54.117** ✅
- [x] `directus.echo-testing.dembrane.com` → LoadBalancer IP: **209.38.54.117** ✅
- [x] `dashboard.echo-testing.dembrane.com` → CNAME: **cname.vercel-dns.com** ✅
- [x] `portal.echo-testing.dembrane.com` → CNAME: **cname.vercel-dns.com** ✅
- [x] DNS records added by lead engineer ✅
- [x] DNS propagation verified ✅

### 1.4 Secrets Management

**Steps**:

1. **Copy dev secrets as template**:
```bash
cd /Users/dattran/Development/echo-gitops

# Copy dev secrets to create testing secrets
cp secrets/sealed-backend-secrets-dev.yaml secrets/sealed-backend-secrets-testing.yaml

# You'll need to:
# 1. Create unsealed secrets first (secrets/backend-secrets-testing.yaml)
# 2. Update with testing-specific values (DB URLs, S3 bucket, etc.)
# 3. Seal them
```

2. **Get testing database credentials from Terraform output**:
```bash
cd infra
terraform workspace select testing
terraform output -json

# Extract:
# - postgres_host
# - postgres_port
# - postgres_user
# - postgres_password
# - postgres_database
# - redis_host
# - redis_port
# - redis_password
```

3. **Create unsealed secret file** (`secrets/backend-secrets-testing.yaml`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backend-secrets
  namespace: echo-testing
type: Opaque
stringData:
  # Database (from Terraform output)
  POSTGRES_HOST: "<postgres_host>"
  POSTGRES_PORT: "<postgres_port>"
  POSTGRES_USER: "<postgres_user>"
  POSTGRES_PASSWORD: "<postgres_password>"
  POSTGRES_DB: "defaultdb"
  
  # Redis (from Terraform output)
  REDIS_HOST: "<redis_host>"
  REDIS_PORT: "<redis_port>"
  REDIS_PASSWORD: "<redis_password>"
  
  # S3 Storage
  STORAGE_S3_BUCKET: "dbr-echo-testing-uploads"
  STORAGE_S3_ACCESS_KEY: "<from_DO_console>"
  STORAGE_S3_SECRET_KEY: "<from_DO_console>"
  
  # Directus
  DIRECTUS_KEY: "<generate_random_32_char_string>"
  DIRECTUS_SECRET: "<generate_random_32_char_string>"
  DIRECTUS_ADMIN_EMAIL: "admin@dembrane.com"
  DIRECTUS_ADMIN_PASSWORD: "<generate_secure_password>"
  
  # Database URLs (constructed)
  POSTGRES_DATABASE_URL: "postgresql://<user>:<pass>@<host>:<port>/defaultdb"
  DIRECTUS_DB_CLIENT: "pg"
  DIRECTUS_DB_HOST: "<postgres_host>"
  DIRECTUS_DB_PORT: "<postgres_port>"
  DIRECTUS_DB_DATABASE: "defaultdb"
  DIRECTUS_DB_USER: "<postgres_user>"
  DIRECTUS_DB_PASSWORD: "<postgres_password>"
  
  # Sentry
  SENTRY_DSN: "<create_new_testing_project_in_sentry>"
  SENTRY_ENVIRONMENT: "testing"
  
  # JWT/Auth
  JWT_SECRET: "<generate_random_64_char_string>"
  
  # LiteLLM / External APIs (reuse dev or create testing-specific)
  LITELLM_API_KEY: "<from_dev_or_new>"
  OPENAI_API_KEY: "<from_dev_or_new>"
  ANTHROPIC_API_KEY: "<from_dev_or_new>"
  
  # Add any other secrets from dev environment
```

4. **Seal the secrets**:
```bash
# Seal for testing cluster
kubeseal --context=do-ams3-dbr-echo-testing-k8s-cluster \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets \
  < secrets/backend-secrets-testing.yaml > secrets/sealed-backend-secrets-testing.yaml

# Apply sealed secret
kubectl --context=do-ams3-dbr-echo-testing-k8s-cluster \
  apply -f secrets/sealed-backend-secrets-testing.yaml

# Verify secret was created
kubectl --context=do-ams3-dbr-echo-testing-k8s-cluster \
  get secret backend-secrets -n echo-testing
```

5. **Delete unsealed secret file** (IMPORTANT):
```bash
rm secrets/backend-secrets-testing.yaml
# Never commit unsealed secrets!
```

### 1.5 Variables Checklist

**Environment Variables for Testing** (to be used in values-testing.yaml):

| Variable | Value | Notes |
|----------|-------|-------|
| `POSTGRES_DATABASE_URL` | From Terraform output | Managed DB |
| `REDIS_HOST` | From Terraform output | Managed Redis |
| `STORAGE_S3_BUCKET` | `dbr-echo-testing-uploads` | Separate bucket |
| `STORAGE_S3_ENDPOINT` | `https://ams3.digitaloceanspaces.com` | Same as dev |
| `DIRECTUS_BASE_URL` | `https://directus.echo-testing.dembrane.com` | Testing domain |
| `ADMIN_BASE_URL` | `https://dashboard.echo-testing.dembrane.com` | If frontend deployed |
| `PARTICIPANT_BASE_URL` | `https://portal.echo-testing.dembrane.com` | If frontend deployed |
| `API_BASE_URL` | `https://api.echo-testing.dembrane.com/api` | Testing API |
| `SENTRY_ENVIRONMENT` | `testing` | Separate in Sentry |
| `DEBUG_MODE` | `1` | Enable debug |

---

## Phase 2: GitOps Configuration (Day 3)

**Goal**: Create Helm values and ArgoCD application for testing environment.

### 2.1 Create Helm Values for Testing

**File**: `helm/echo/values-testing.yaml`

**Create new file** (copy from values.yaml and modify):

```yaml
global:
  imageTag: "testing"  # Will be updated by CI/CD
  registry: "registry.digitalocean.com/dbr-cr"

# Common configuration shared across services
common:
  env:
    # Core application config
    DEBUG_MODE: "1"
    DIRECTUS_BASE_URL: "https://directus.echo-testing.dembrane.com"
    ADMIN_BASE_URL: "https://dashboard.echo-testing.dembrane.com"
    PARTICIPANT_BASE_URL: "https://portal.echo-testing.dembrane.com"
    API_BASE_URL: "https://api.echo-testing.dembrane.com/api"
    NEO4J_URI: "bolt://echo-neo4j:7687"
    NEO4J_USERNAME: "neo4j"
    DISABLE_CORS: "0"
    DISABLE_REDACTION: "1"
    DISABLE_SENTRY: "0"
    SERVE_API_DOCS: "1"

    # Feature flags (same as dev)
    ENABLE_CHAT_AUTO_SELECT: "1"
    ENABLE_AUDIO_LIGHTRAG_INPUT: "0"
    TRANSCRIPTION_PROVIDER: "Dembrane-25-09"
    ENABLE_ASSEMBLYAI_TRANSCRIPTION: "0"
    ENABLE_LITELLM_WHISPER_TRANSCRIPTION: "0"
    ENABLE_RUNPOD_WHISPER_TRANSCRIPTION: "0"
    ENABLE_ENGLISH_TRANSCRIPTION_WITH_LITELLM: "0"
    RUNPOD_WHISPER_MAX_REQUEST_THRESHOLD: "30"
    ENABLE_RUNPOD_DIARIZATION: "0"
    DISABLE_MULTILINGUAL_DIARIZATION: "1"
    RUNPOD_DIARIZATION_TIMEOUT: "30"

    # Storage config
    STORAGE_S3_REGION: "us-east-1"
    STORAGE_S3_ENDPOINT: "https://ams3.digitaloceanspaces.com"
    STORAGE_S3_BUCKET: "dbr-echo-testing-uploads"

    # LiteLLM API Version
    LIGHTRAG_LITELLM_API_VERSION: "2023-05-15"

directus:
  replicaCount: 1
  maxReplicaCount: 1
  image:
    repository: "dbr-echo-directus"
  service:
    port: 8055
  resources:
    requests:
      cpu: "300m"
      memory: "512Mi"
    limits:
      cpu: "800m"
      memory: "1Gi"
  env:
    PUBLIC_URL: "https://directus.echo-testing.dembrane.com"
    CORS_ORIGIN: "https://dashboard.echo-testing.dembrane.com,https://portal.echo-testing.dembrane.com,http://localhost:5173,http://localhost:5174"
    SESSION_COOKIE_NAME: "dembrane_session_token_testing"
    SESSION_COOKIE_DOMAIN: "echo-testing.dembrane.com"
    USER_REGISTER_URL_ALLOW_LIST: "https://dashboard.echo-testing.dembrane.com/verify-email,http://localhost:5173/verify-email"
    PASSWORD_RESET_URL_ALLOW_LIST: "https://dashboard.echo-testing.dembrane.com/password-reset,http://localhost:5173/password-reset"
    USER_INVITE_URL_ALLOW_LIST: "https://dashboard.echo-testing.dembrane.com/invite,http://localhost:5173/invite"
    AUTH_GOOGLE_ALLOW_PUBLIC_REGISTRATION: "false"
    AUTH_GOOGLE_DEFAULT_ROLE_ID: "2446660a-ab6c-4801-ad69-5711030cba83"
    AUTH_GOOGLE_REDIRECT_ALLOW_LIST: "https://dashboard.echo-testing.dembrane.com/en-US/projects,https://dashboard.echo-testing.dembrane.com/nl-NL/projects"

apiServer:
  replicaCount: 1
  maxReplicaCount: 5
  image:
    repository: "dbr-echo-server"
  service:
    port: 8000
  resources:
    requests:
      cpu: "300m"
      memory: "1Gi"
    limits:
      cpu: "800m"
      memory: "2Gi"

worker:
  replicaCount: 1
  maxReplicaCount: 3
  image:
    repository: "dbr-echo-server"
  resources:
    requests:
      cpu: "300m"
      memory: "1Gi"
    limits:
      cpu: "800m"
      memory: "2Gi"

workerCpu:
  replicaCount: 1
  maxReplicaCount: 2
  image:
    repository: "dbr-echo-server"
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1"
      memory: "2Gi"
  env:
    CPU_WORKER_PROCESSES: "1"
    CPU_WORKER_THREADS: "1"

workerScheduler:
  replicaCount: 1
  maxReplicaCount: 1
  image:
    repository: "dbr-echo-server"
  resources:
    requests:
      cpu: "300m"
      memory: "512Mi"
    limits:
      cpu: "600m"
      memory: "1Gi"

neo4j:
  image:
    repository: "neo4j"
    tag: "5.18.0-community"
  password: "admin@dembrane"
  storage:
    size: "5Gi"  # Smaller than dev
  config:
    pagecacheSize: "256M"
    heapSize: "256M"
  resources:
    requests:
      cpu: "300m"
      memory: "512Mi"
    limits:
      cpu: "800m"
      memory: "2Gi"

ingress:
  enabled: true
  className: "nginx"
  email: "admin@dembrane.com"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
  clusterIssuerName: "letsencrypt-prod"
  domain: "echo-testing.dembrane.com"
  hosts:
    directus: "directus.echo-testing.dembrane.com"
    api: "api.echo-testing.dembrane.com"
  tls:
    - secretName: "echo-testing-tls"
      hosts:
        - "directus.echo-testing.dembrane.com"
        - "api.echo-testing.dembrane.com"

storage:
  storageClassName: "do-block-storage"

rollout:
  maxUnavailable: "0%"
  maxSurge: "25%"
```

### 2.2 Create ArgoCD Application

**File**: `argo/echo-testing.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: echo-testing
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/dembrane/echo-gitops.git'
    targetRevision: main
    path: helm/echo
    helm:
      valueFiles:
        - values-testing.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: echo-testing
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 2.3 Apply ArgoCD Application

```bash
# Switch to testing cluster context
kubectl config use-context do-ams3-dbr-echo-testing-k8s-cluster

# Apply ArgoCD application
kubectl apply -f argo/echo-testing.yaml

# Verify ArgoCD picked it up
kubectl get application -n argocd echo-testing

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser: https://localhost:8080
# Username: admin
# Password: <from above command>
# Check echo-testing application status
```

### 2.4 Commit GitOps Changes

```bash
cd /Users/dattran/Development/echo-gitops

git add helm/echo/values-testing.yaml
git add argo/echo-testing.yaml
git add secrets/sealed-backend-secrets-testing.yaml

git commit -m "Add testing environment configuration"
git push origin main
```

---

## Phase 3: CI/CD Pipeline (Days 4-5)

**Goal**: Create GitHub Actions workflows in the echo repository to automate testing and deployment.

### 3.1 Create PR Validation Workflow

**File**: `.github/workflows/pr-testing.yml` (in echo repo)

```yaml
name: PR to Testing Branch

on:
  pull_request:
    branches:
      - testing
    types: [opened, synchronize, reopened]

env:
  REGISTRY: registry.digitalocean.com/dbr-cr
  PYTHON_VERSION: "3.11"

jobs:
  lint-and-type-check:
    name: Lint & Type Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install dependencies
        run: |
          cd echo/server
          pip install -r requirements.lock

      - name: Run Ruff Lint
        run: |
          cd echo/server
          ruff check .

      - name: Run Ruff Format Check
        run: |
          cd echo/server
          ruff format --check .

      - name: Run MyPy Type Check
        run: |
          cd echo/server
          mypy dembrane/ --ignore-missing-imports

  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install dependencies
        run: |
          cd echo/server
          pip install -r requirements.lock

      - name: Run Unit Tests
        run: |
          cd echo/server
          pytest tests/ -v -m "not integration and not slow" --maxfail=3

  build-images:
    name: Build Docker Images (validation only)
    runs-on: ubuntu-latest
    needs: [lint-and-type-check, unit-tests]
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build API Server Image
        uses: docker/build-push-action@v5
        with:
          context: ./echo/server
          file: ./echo/server/Dockerfile
          push: false
          tags: ${{ env.REGISTRY }}/dbr-echo-server:pr-${{ github.event.pull_request.number }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Build Directus Image
        uses: docker/build-push-action@v5
        with:
          context: ./echo/directus
          file: ./echo/directus/Dockerfile
          push: false
          tags: ${{ env.REGISTRY }}/dbr-echo-directus:pr-${{ github.event.pull_request.number }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  auto-merge:
    name: Auto-merge PR
    runs-on: ubuntu-latest
    needs: [build-images]
    permissions:
      pull-requests: write
      contents: write
    steps:
      - name: Auto-merge PR
        uses: pascalgn/automerge-action@v0.16.2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          MERGE_LABELS: ""
          MERGE_METHOD: "squash"
          MERGE_COMMIT_MESSAGE: "pull-request-title"
          MERGE_RETRIES: 3
          MERGE_RETRY_SLEEP: 10000
```

### 3.2 Create Deploy to Testing Workflow

**File**: `.github/workflows/deploy-testing.yml` (in echo repo)

```yaml
name: Deploy to Testing

on:
  push:
    branches:
      - testing

env:
  REGISTRY: registry.digitalocean.com/dbr-cr
  GITOPS_REPO: dembrane/echo-gitops
  PYTHON_VERSION: "3.11"

jobs:
  build-and-push:
    name: Build & Push Images
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.tag }}
    steps:
      - uses: actions/checkout@v4

      - name: Generate image tag
        id: meta
        run: |
          SHORT_SHA=$(echo ${{ github.sha }} | cut -c1-7)
          echo "tag=$SHORT_SHA" >> $GITHUB_OUTPUT
          echo "📦 Image tag: $SHORT_SHA"

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to DigitalOcean Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.DO_REGISTRY_TOKEN }}
          password: ${{ secrets.DO_REGISTRY_TOKEN }}

      - name: Build and Push API Server
        uses: docker/build-push-action@v5
        with:
          context: ./echo/server
          file: ./echo/server/Dockerfile
          push: true
          tags: |
            ${{ env.REGISTRY }}/dbr-echo-server:${{ steps.meta.outputs.tag }}
            ${{ env.REGISTRY }}/dbr-echo-server:testing
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Build and Push Directus
        uses: docker/build-push-action@v5
        with:
          context: ./echo/directus
          file: ./echo/directus/Dockerfile
          push: true
          tags: |
            ${{ env.REGISTRY }}/dbr-echo-directus:${{ steps.meta.outputs.tag }}
            ${{ env.REGISTRY }}/dbr-echo-directus:testing
          cache-from: type=gha
          cache-to: type=gha,mode=max

  update-gitops:
    name: Update GitOps Repo
    runs-on: ubuntu-latest
    needs: [build-and-push]
    steps:
      - name: Checkout GitOps repo
        uses: actions/checkout@v4
        with:
          repository: ${{ env.GITOPS_REPO }}
          token: ${{ secrets.GITOPS_PAT }}
          ref: main

      - name: Update image tag in values-testing.yaml
        run: |
          IMAGE_TAG="${{ needs.build-and-push.outputs.image-tag }}"
          echo "Updating imageTag to: $IMAGE_TAG"
          
          sed -i "s/imageTag: \".*\"/imageTag: \"$IMAGE_TAG\"/" helm/echo/values-testing.yaml
          
          echo "Updated values-testing.yaml:"
          grep "imageTag:" helm/echo/values-testing.yaml

      - name: Commit and push changes
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          
          git add helm/echo/values-testing.yaml
          git commit -m "Update testing image tag to ${{ needs.build-and-push.outputs.image-tag }}"
          git push origin main

  wait-for-deployment:
    name: Wait for ArgoCD Deployment
    runs-on: ubuntu-latest
    needs: [update-gitops, build-and-push]
    steps:
      - uses: actions/checkout@v4

      - name: Wait for deployment
        run: |
          echo "⏳ Waiting for ArgoCD to sync and deploy..."
          echo "Image tag: ${{ needs.build-and-push.outputs.image-tag }}"
          
          MAX_WAIT=600  # 10 minutes
          INTERVAL=15
          ELAPSED=0
          
          while [ $ELAPSED -lt $MAX_WAIT ]; do
            echo "Checking API health (${ELAPSED}s elapsed)..."
            
            if curl -f -s https://api.echo-testing.dembrane.com/health > /dev/null 2>&1; then
              echo "✅ API is healthy!"
              exit 0
            fi
            
            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
          done
          
          echo "❌ Deployment did not become healthy within ${MAX_WAIT}s"
          exit 1

  smoke-tests:
    name: Run Smoke Tests
    runs-on: ubuntu-latest
    needs: [wait-for-deployment, build-and-push]
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install dependencies
        run: |
          cd echo/server
          pip install -r requirements.lock
          pip install requests

      - name: Run Smoke Tests
        env:
          TEST_API_URL: https://api.echo-testing.dembrane.com
          TEST_DIRECTUS_URL: https://directus.echo-testing.dembrane.com
        run: |
          cd echo/server
          pytest tests/smoke/ -v --timeout=600 --maxfail=1

  e2e-tests:
    name: Run E2E Tests
    runs-on: ubuntu-latest
    needs: [smoke-tests]
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Install pnpm
        uses: pnpm/action-setup@v2
        with:
          version: 8

      - name: Install dependencies
        run: |
          cd echo/frontend
          pnpm install

      - name: Install Playwright Browsers
        run: |
          cd echo/frontend
          pnpm exec playwright install --with-deps chromium

      - name: Run Playwright Tests
        env:
          TEST_BASE_URL: https://api.echo-testing.dembrane.com
        run: |
          cd echo/frontend
          pnpm exec playwright test

      - name: Upload Playwright Report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: playwright-report
          path: echo/frontend/playwright-report/
          retention-days: 7

  notify-slack:
    name: Notify Slack
    runs-on: ubuntu-latest
    needs: [build-and-push, smoke-tests, e2e-tests]
    if: always()
    steps:
      - name: Determine status
        id: status
        run: |
          if [ "${{ needs.smoke-tests.result }}" == "success" ] && [ "${{ needs.e2e-tests.result }}" == "success" ]; then
            echo "result=success" >> $GITHUB_OUTPUT
            echo "emoji=✅" >> $GITHUB_OUTPUT
            echo "color=good" >> $GITHUB_OUTPUT
          else
            echo "result=failure" >> $GITHUB_OUTPUT
            echo "emoji=❌" >> $GITHUB_OUTPUT
            echo "color=danger" >> $GITHUB_OUTPUT
          fi

      - name: Send Slack notification
        uses: slackapi/slack-github-action@v1.24.0
        with:
          payload: |
            {
              "attachments": [
                {
                  "color": "${{ steps.status.outputs.color }}",
                  "blocks": [
                    {
                      "type": "header",
                      "text": {
                        "type": "plain_text",
                        "text": "${{ steps.status.outputs.emoji }} Testing Deployment: ${{ steps.status.outputs.result }}"
                      }
                    },
                    {
                      "type": "section",
                      "fields": [
                        {
                          "type": "mrkdwn",
                          "text": "*Repository:*\necho"
                        },
                        {
                          "type": "mrkdwn",
                          "text": "*Branch:*\ntesting"
                        },
                        {
                          "type": "mrkdwn",
                          "text": "*Image Tag:*\n`${{ needs.build-and-push.outputs.image-tag }}`"
                        },
                        {
                          "type": "mrkdwn",
                          "text": "*Commit:*\n<https://github.com/${{ github.repository }}/commit/${{ github.sha }}|${{ github.sha }}>"
                        }
                      ]
                    },
                    {
                      "type": "section",
                      "fields": [
                        {
                          "type": "mrkdwn",
                          "text": "*Smoke Tests:*\n${{ needs.smoke-tests.result }}"
                        },
                        {
                          "type": "mrkdwn",
                          "text": "*E2E Tests:*\n${{ needs.e2e-tests.result }}"
                        }
                      ]
                    },
                    {
                      "type": "section",
                      "text": {
                        "type": "mrkdwn",
                        "text": "*Links:*\n• <https://api.echo-testing.dembrane.com|API>\n• <https://directus.echo-testing.dembrane.com|Directus>\n• <https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}|GitHub Actions>"
                      }
                    },
                    {
                      "type": "section",
                      "text": {
                        "type": "mrkdwn",
                        "text": "${{ steps.status.outputs.result == 'failure' && '⚠️ *Rollback Instructions:*\n```\ncd echo-gitops\ngit revert HEAD\ngit push origin main\n```\nOr keep for debugging and fix forward.' || '🎉 All tests passed! Environment is stable.' }}"
                      }
                    }
                  ]
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

### 3.3 Required GitHub Secrets

Add the following secrets to the **echo repository** (Settings → Secrets and variables → Actions):

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `DO_REGISTRY_TOKEN` | DigitalOcean registry access token | DO Console → API → Generate New Token |
| `GITOPS_PAT` | GitHub Personal Access Token with repo access | GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate (repo permissions) |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL | Slack → Apps → Incoming Webhooks → Add to #alerts-devops |

**Steps to create GITOPS_PAT**:
1. Go to GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Click "Generate new token"
3. Name: "Echo CI/CD GitOps Access"
4. Expiration: 1 year (or custom)
5. Repository access: "Only select repositories" → select `echo-gitops`
6. Permissions:
   - Contents: Read and write
   - Metadata: Read-only
7. Generate token and copy
8. Add to echo repository secrets as `GITOPS_PAT`

**Steps to create Slack webhook**:
1. Go to Slack workspace
2. Click on workspace name → Settings & administration → Manage apps
3. Search for "Incoming Webhooks"
4. Add to Slack
5. Choose channel: `#alerts-devops`
6. Copy Webhook URL
7. Add to echo repository secrets as `SLACK_WEBHOOK_URL`

---

## Phase 4: Testing Infrastructure (Days 6-7)

**Goal**: Create smoke tests and Playwright E2E tests in the echo repository.

### 4.1 Create Smoke Tests

**Directory**: `echo/server/tests/smoke/` (in echo repo)

**File**: `echo/server/tests/smoke/conftest.py`

```python
import os
import pytest

@pytest.fixture(scope="session")
def api_url():
    """Base API URL for smoke tests"""
    return os.getenv("TEST_API_URL", "https://api.echo-testing.dembrane.com")

@pytest.fixture(scope="session")
def directus_url():
    """Directus URL for smoke tests"""
    return os.getenv("TEST_DIRECTUS_URL", "https://directus.echo-testing.dembrane.com")
```

**File**: `echo/server/tests/smoke/test_health_checks.py`

```python
import pytest
import requests

@pytest.mark.smoke
def test_api_health_endpoint(api_url):
    """Test that API health endpoint is accessible"""
    response = requests.get(f"{api_url}/health", timeout=10)
    assert response.status_code == 200
    data = response.json()
    assert data.get("status") == "healthy"

@pytest.mark.smoke
def test_api_docs_accessible(api_url):
    """Test that API docs are accessible"""
    response = requests.get(f"{api_url}/docs", timeout=10)
    assert response.status_code == 200

@pytest.mark.smoke
def test_directus_health(directus_url):
    """Test that Directus is accessible"""
    response = requests.get(f"{directus_url}/server/ping", timeout=10)
    assert response.status_code == 200
    assert response.text == "pong"

@pytest.mark.smoke
def test_database_connection(api_url):
    """Test that API can connect to database"""
    # Assuming you have a health check that includes DB status
    response = requests.get(f"{api_url}/health/database", timeout=10)
    assert response.status_code == 200
    data = response.json()
    assert data.get("database") == "connected"

@pytest.mark.smoke
def test_redis_connection(api_url):
    """Test that API can connect to Redis"""
    response = requests.get(f"{api_url}/health/redis", timeout=10)
    assert response.status_code == 200
    data = response.json()
    assert data.get("redis") == "connected"
```

**File**: `echo/server/tests/smoke/test_critical_flows.py`

```python
import pytest
import requests

@pytest.mark.smoke
def test_create_project(api_url):
    """Test creating a project"""
    # This assumes you have test credentials
    # You may need to implement proper auth flow
    
    # Step 1: Authenticate (if needed)
    auth_response = requests.post(
        f"{api_url}/auth/login",
        json={
            "email": "test@echo-testing.dembrane.com",
            "password": "test_password"
        },
        timeout=10
    )
    
    if auth_response.status_code != 200:
        pytest.skip("Auth not configured for smoke tests")
    
    token = auth_response.json().get("token")
    headers = {"Authorization": f"Bearer {token}"}
    
    # Step 2: Create project
    response = requests.post(
        f"{api_url}/api/projects",
        json={
            "name": "Smoke Test Project",
            "language": "en",
            "description": "Automated smoke test"
        },
        headers=headers,
        timeout=10
    )
    
    assert response.status_code in [200, 201]
    data = response.json()
    assert "id" in data
    assert data["name"] == "Smoke Test Project"
    
    # Step 3: Clean up (delete project)
    project_id = data["id"]
    delete_response = requests.delete(
        f"{api_url}/api/projects/{project_id}",
        headers=headers,
        timeout=10
    )
    assert delete_response.status_code in [200, 204]

@pytest.mark.smoke
def test_upload_audio_chunk(api_url):
    """Test uploading an audio chunk"""
    # Create test audio file
    import io
    
    # Get auth token
    auth_response = requests.post(
        f"{api_url}/auth/login",
        json={
            "email": "test@echo-testing.dembrane.com",
            "password": "test_password"
        },
        timeout=10
    )
    
    if auth_response.status_code != 200:
        pytest.skip("Auth not configured for smoke tests")
    
    token = auth_response.json().get("token")
    headers = {"Authorization": f"Bearer {token}"}
    
    # Create project and conversation first
    project_response = requests.post(
        f"{api_url}/api/projects",
        json={"name": "Audio Test Project", "language": "en"},
        headers=headers,
        timeout=10
    )
    project_id = project_response.json()["id"]
    
    conversation_response = requests.post(
        f"{api_url}/api/conversations",
        json={
            "project_id": project_id,
            "participant_name": "Test Participant"
        },
        headers=headers,
        timeout=10
    )
    conversation_id = conversation_response.json()["id"]
    
    # Upload small test audio chunk
    test_audio = b'\x00' * 1024  # 1KB of silence
    files = {
        "file": ("test.webm", io.BytesIO(test_audio), "audio/webm")
    }
    
    response = requests.post(
        f"{api_url}/api/conversations/{conversation_id}/chunks",
        files=files,
        headers=headers,
        timeout=30
    )
    
    assert response.status_code in [200, 201]
    
    # Clean up
    requests.delete(f"{api_url}/api/projects/{project_id}", headers=headers, timeout=10)
```

**File**: `echo/server/tests/smoke/test_integrations.py`

```python
import pytest
import requests

@pytest.mark.smoke
def test_s3_connectivity(api_url):
    """Test that S3 storage is accessible"""
    response = requests.get(f"{api_url}/health/storage", timeout=10)
    assert response.status_code == 200
    data = response.json()
    assert data.get("storage") == "connected"

@pytest.mark.smoke  
def test_neo4j_connectivity(api_url):
    """Test that Neo4j is accessible"""
    response = requests.get(f"{api_url}/health/neo4j", timeout=10)
    assert response.status_code == 200
    data = response.json()
    assert data.get("neo4j") == "connected"
```

**Update pytest configuration** (`echo/server/pyproject.toml` or `pytest.ini`):

```toml
[tool.pytest.ini_options]
markers = [
    "smoke: smoke tests for deployment validation",
    "integration: integration tests requiring external services",
    "slow: tests that take > 1 second",
    "e2e: end-to-end tests"
]
```

### 4.2 Create Playwright E2E Tests

**Directory**: `echo/frontend/tests/e2e/` (in echo repo)

**File**: `echo/frontend/playwright.config.ts`

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  
  use: {
    baseURL: process.env.TEST_BASE_URL || 'https://dashboard.echo-testing.dembrane.com',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  webServer: process.env.CI ? undefined : {
    command: 'pnpm dev',
    port: 5173,
    reuseExistingServer: !process.env.CI,
  },
});
```

**File**: `echo/frontend/tests/e2e/auth.spec.ts`

```typescript
import { test, expect } from '@playwright/test';

test.describe('Authentication', () => {
  test('should load login page', async ({ page }) => {
    await page.goto('/login');
    
    await expect(page).toHaveTitle(/Echo/);
    await expect(page.locator('input[type="email"]')).toBeVisible();
    await expect(page.locator('input[type="password"]')).toBeVisible();
  });

  test('should login with valid credentials', async ({ page }) => {
    await page.goto('/login');
    
    // Fill login form
    await page.fill('input[type="email"]', 'test@echo-testing.dembrane.com');
    await page.fill('input[type="password"]', 'test_password');
    await page.click('button[type="submit"]');
    
    // Wait for navigation to dashboard
    await page.waitForURL('**/projects', { timeout: 10000 });
    
    // Verify logged in
    await expect(page.locator('text=Projects')).toBeVisible();
  });

  test('should show error for invalid credentials', async ({ page }) => {
    await page.goto('/login');
    
    await page.fill('input[type="email"]', 'invalid@example.com');
    await page.fill('input[type="password"]', 'wrongpassword');
    await page.click('button[type="submit"]');
    
    // Check for error message
    await expect(page.locator('text=/invalid|error|wrong/i')).toBeVisible({ timeout: 5000 });
  });
});
```

**File**: `echo/frontend/tests/e2e/projects.spec.ts`

```typescript
import { test, expect } from '@playwright/test';

test.describe('Projects', () => {
  test.beforeEach(async ({ page }) => {
    // Login first
    await page.goto('/login');
    await page.fill('input[type="email"]', 'test@echo-testing.dembrane.com');
    await page.fill('input[type="password"]', 'test_password');
    await page.click('button[type="submit"]');
    await page.waitForURL('**/projects');
  });

  test('should create a new project', async ({ page }) => {
    // Click create project button
    await page.click('button:has-text("New Project")');
    
    // Fill project form
    await page.fill('input[name="name"]', 'E2E Test Project');
    await page.selectOption('select[name="language"]', 'en');
    await page.fill('textarea[name="description"]', 'Automated E2E test');
    
    // Submit form
    await page.click('button[type="submit"]:has-text("Create")');
    
    // Verify project created
    await expect(page.locator('text=E2E Test Project')).toBeVisible({ timeout: 5000 });
  });

  test('should display projects list', async ({ page }) => {
    await expect(page.locator('[data-testid="projects-list"]')).toBeVisible();
  });
});
```

**File**: `echo/frontend/tests/e2e/conversation.spec.ts`

```typescript
import { test, expect } from '@playwright/test';

test.describe('Conversations', () => {
  test.beforeEach(async ({ page }) => {
    // Login and create/navigate to a project
    await page.goto('/login');
    await page.fill('input[type="email"]', 'test@echo-testing.dembrane.com');
    await page.fill('input[type="password"]', 'test_password');
    await page.click('button[type="submit"]');
    await page.waitForURL('**/projects');
  });

  test('should create a conversation', async ({ page }) => {
    // Navigate to first project
    await page.click('[data-testid="project-card"]:first-child');
    
    // Create new conversation
    await page.click('button:has-text("New Conversation")');
    await page.fill('input[name="participant_name"]', 'E2E Test Participant');
    await page.click('button[type="submit"]:has-text("Start")');
    
    // Verify conversation started
    await expect(page.locator('text=E2E Test Participant')).toBeVisible({ timeout: 5000 });
  });

  test('should display conversation interface', async ({ page }) => {
    // Navigate to existing conversation
    await page.click('[data-testid="project-card"]:first-child');
    await page.click('[data-testid="conversation-item"]:first-child');
    
    // Check for conversation UI elements
    await expect(page.locator('[data-testid="conversation-view"]')).toBeVisible();
  });
});
```

**Update package.json** to add test scripts:

```json
{
  "scripts": {
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "test:e2e:debug": "playwright test --debug"
  }
}
```

### 4.3 Create Test User and Seed Data

**Script**: `echo/server/scripts/seed_testing_data.py`

```python
"""
Script to seed testing environment with initial data
Run once after testing cluster is set up
"""

import os
import sys
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from dembrane.database import Base
from dembrane.models import User, Project, Conversation

# Get database URL from environment or use default
DATABASE_URL = os.getenv(
    "POSTGRES_DATABASE_URL",
    "postgresql://user:pass@host:5432/defaultdb"
)

def seed_testing_data():
    """Seed testing environment with sample data"""
    
    engine = create_engine(DATABASE_URL)
    SessionLocal = sessionmaker(bind=engine)
    db = SessionLocal()
    
    try:
        print("🌱 Seeding testing environment...")
        
        # Create test user
        test_user = User(
            email="test@echo-testing.dembrane.com",
            first_name="Test",
            last_name="User",
            # Set hashed password for "test_password"
            # You'll need to use your password hashing function
        )
        db.add(test_user)
        db.commit()
        print(f"✅ Created test user: {test_user.email}")
        
        # Create sample project
        sample_project = Project(
            name="Sample Project",
            language="en",
            description="Pre-seeded project for testing",
            owner_id=test_user.id
        )
        db.add(sample_project)
        db.commit()
        print(f"✅ Created sample project: {sample_project.name}")
        
        # Create sample conversation
        sample_conversation = Conversation(
            project_id=sample_project.id,
            participant_name="Sample Participant",
            status="active"
        )
        db.add(sample_conversation)
        db.commit()
        print(f"✅ Created sample conversation: {sample_conversation.id}")
        
        print("🎉 Testing environment seeded successfully!")
        
    except Exception as e:
        print(f"❌ Error seeding data: {e}")
        db.rollback()
        raise
    finally:
        db.close()

if __name__ == "__main__":
    seed_testing_data()
```

**Run the seed script** (after testing cluster is deployed):

```bash
# SSH into API pod or run locally with testing DB credentials
cd echo/server

# Set environment variables
export POSTGRES_DATABASE_URL="postgresql://..."

# Run seed script
python scripts/seed_testing_data.py
```

---

## Phase 5: Integration & Validation (Day 8)

**Goal**: Test the entire pipeline end-to-end and document everything.

### 5.1 End-to-End Pipeline Test

**Checklist**:

1. **Create testing branch in echo repo**:
```bash
cd /Users/dattran/Development/echo
git checkout main
git pull
git checkout -b testing
git push -u origin testing
```

2. **Create a test PR**:
```bash
# Make a small change (e.g., update README)
echo "# Testing" >> README.md
git add README.md
git commit -m "test: trigger testing pipeline"
git checkout -b test/pipeline-validation
git push -u origin test/pipeline-validation

# Create PR to testing branch via GitHub UI
```

3. **Verify PR workflow runs**:
- Go to GitHub Actions
- Check "PR to Testing Branch" workflow runs
- Verify: lint → type check → unit tests → build → auto-merge

4. **Verify deployment workflow runs**:
- After PR merges, check "Deploy to Testing" workflow
- Verify: build → push → update gitops → wait → smoke tests → e2e → slack

5. **Verify ArgoCD syncs**:
```bash
kubectl --context=do-ams3-dbr-echo-testing-k8s-cluster \
  get application -n argocd echo-testing

# Check status
kubectl --context=do-ams3-dbr-echo-testing-k8s-cluster \
  get pods -n echo-testing
```

6. **Verify Slack notification**:
- Check #alerts-devops channel
- Should see deployment notification with test results

7. **Manually test the environment**:
```bash
# Test API
curl https://api.echo-testing.dembrane.com/health

# Test Directus
curl https://directus.echo-testing.dembrane.com/server/ping

# Test in browser
open https://api.echo-testing.dembrane.com/docs
```

### 5.2 Documentation

**File**: `TESTING_ENVIRONMENT.md` (in echo-gitops repo)

```markdown
# Testing Environment

## Overview

The testing environment is a full replica of production/dev infrastructure used for automated testing and validation before deploying to production.

## Access

- **API**: https://api.echo-testing.dembrane.com
- **Directus**: https://directus.echo-testing.dembrane.com
- **API Docs**: https://api.echo-testing.dembrane.com/docs
- **ArgoCD**: Port-forward required (see below)

## Architecture

- **Cluster**: DO Kubernetes (2-4 nodes, s-4vcpu-8gb)
- **Database**: Managed Postgres (db-s-1vcpu-1gb)
- **Cache**: Managed Redis (db-s-1vcpu-1gb)
- **Storage**: S3 bucket (dbr-echo-testing-uploads)
- **Deployment**: ArgoCD (auto-sync from main branch)

## Deployment Flow

1. Create PR to `testing` branch in echo repo
2. CI runs: linting, type checks, unit tests, build validation
3. On success: PR auto-merges to `testing` branch
4. On merge: CI builds images, tags as `<commit-sha>` and `testing`
5. CI updates `echo-gitops/helm/echo/values-testing.yaml` with new imageTag
6. ArgoCD detects change and deploys to testing cluster
7. Post-deployment: smoke tests + Playwright E2E tests run
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

### E2E Tests

```bash
cd echo/frontend

# Set test environment
export TEST_BASE_URL=https://dashboard.echo-testing.dembrane.com

# Run Playwright tests
pnpm exec playwright test

# Run with UI
pnpm exec playwright test --ui

# Debug mode
pnpm exec playwright test --debug
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
sed -i 's/imageTag: "abc123"/imageTag: "xyz789"/' helm/echo/values-testing.yaml

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

# 4. Delete unsealed file
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

Currently no Prometheus/Grafana for testing (to save costs).
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
kubectl scale deployment -n echo-testing \
  echo-api-server --replicas=1
kubectl scale deployment -n echo-testing \
  echo-worker --replicas=1
kubectl scale deployment -n echo-testing \
  echo-directus --replicas=1
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

- [Testing Strategy](../echo/notes_TESTING_STRATEGY.md)
- [Deployment Rules](.cursor/rules/deploy-monitoring.mdc)
- [Main Infrastructure](infra/main.tf)
```

### 5.3 Update Deployment Rules

**File**: `.cursor/rules/deploy-monitoring.mdc`

Add section for testing environment:

```markdown
### Testing Environment Deployment

Use this workflow for deploying to the testing environment via the automated CI/CD pipeline.

#### Overview
- Testing deploys automatically from `testing` branch in echo repo
- CI/CD handles: build → test → deploy → validate
- Manual interventions should be rare

#### Standard Workflow (Recommended)

1. Create feature branch and PR to `testing`:
```bash
cd echo
git checkout testing
git pull
git checkout -b feature/my-feature
# Make changes
git push -u origin feature/my-feature
# Create PR to testing branch on GitHub
```

2. PR checks run automatically:
- Linting (ruff)
- Type checking (mypy)
- Unit tests (pytest)
- Build validation

3. On success, PR auto-merges to testing

4. Deployment pipeline runs:
- Builds Docker images
- Tags as `<commit-sha>` and `testing`
- Updates gitops repo
- ArgoCD deploys
- Smoke tests run
- E2E tests run
- Slack notification sent

#### Manual Deployment (Emergency Only)

If you need to bypass the PR process:

```bash
cd echo
git checkout testing
# Make urgent fix
git commit -am "fix: urgent issue"
git push origin testing
# Deployment triggers automatically
```

#### Monitoring Deployment

Check GitHub Actions:
- PR workflow: Validation before merge
- Deploy workflow: Build, deploy, test

Check ArgoCD:
```bash
kubectl get application -n argocd echo-testing
```

Check Slack:
- #alerts-devops will receive deployment notifications

#### Rollback

If tests fail or issues detected:

**Option 1: Revert commit** (cleanest)
```bash
cd echo-gitops
git revert HEAD
git push origin main
```

**Option 2: Manual imageTag update**
```bash
cd echo-gitops
# Edit helm/echo/values-testing.yaml
# Change imageTag to previous working version
git add helm/echo/values-testing.yaml
git commit -m "Rollback testing to <previous-sha>"
git push origin main
```

#### Debugging

**Check pod status:**
```bash
kubectl --context=do-ams3-dbr-echo-testing-k8s-cluster \
  get pods -n echo-testing
```

**Check logs:**
```bash
kubectl logs -n echo-testing deployment/echo-api-server -f
```

**Check tests:**
```bash
# Go to GitHub Actions
# Find Deploy to Testing workflow
# Check smoke-tests and e2e-tests jobs
```

#### Guardrails
- All changes must pass tests before deploying
- Smoke tests validate critical functionality post-deployment
- E2E tests validate user flows
- Failed tests trigger Slack alerts with rollback instructions
- Testing environment mirrors prod/dev architecture
```

---

## Implementation Timeline Summary

| Phase | Duration | Deliverables | Status |
|-------|----------|--------------|--------|
| **Phase 1** | Days 1-2 | Terraform setup, DNS, secrets | ✅ Completed |
| **Phase 2** | Day 3 | Helm values, ArgoCD app | ✅ Completed |
| **Phase 3** | Days 4-5 | GitHub Actions workflows | ⏳ Not started |
| **Phase 4** | Days 6-7 | Smoke tests, Playwright tests | ⏳ Not started |
| **Phase 5** | Day 8 | E2E validation, documentation | ⏳ Not started |

## Prerequisites Before Starting

- [x] DigitalOcean account with sufficient quota for new cluster
- [x] GitHub account with admin access to echo and echo-gitops repos
- [ ] Slack workspace access to create webhooks
- [ ] Sentry account to create testing project
- [x] DNS access to create new records (*.echo-testing.dembrane.com)
- [x] Terraform installed locally
- [x] kubectl and doctl installed locally
- [x] kubeseal installed locally

## Success Criteria

At the end of implementation, you should be able to:

1. Create a PR to `testing` branch → auto-merge on test pass
2. Merge triggers deployment to testing cluster
3. Post-deployment tests run automatically (smoke + E2E)
4. Slack notification sent with results and rollback instructions
5. Testing environment accessible at echo-testing.dembrane.com
6. Rollback possible via git revert or manual imageTag update
7. All documentation complete and accessible

## Next Steps

1. Review this implementation plan
2. Ensure all prerequisites are met
3. Start with Phase 1: Infrastructure Setup
4. Follow each phase sequentially
5. Test thoroughly after each phase
6. Update documentation as you go

## Questions or Issues?

- Check troubleshooting sections in each phase
- Review logs in GitHub Actions, ArgoCD, kubectl
- Check Slack #alerts-devops for notifications
- Refer to TESTING_ENVIRONMENT.md for operational details

---

---

## Phase 1 Completion Summary

### Infrastructure Created ✅
- **Kubernetes Cluster**: dbr-echo-testing-k8s-cluster
  - Cluster ID: a4928776-f7e8-415d-ba00-e89a661b2a7a
  - VPC: 117cb9fd-6fb3-4f10-94a0-62bf04943a80 (10.10.12.0/24)
  - Nodes: 2x s-4vcpu-8gb (autoscale 2-4)
  - LoadBalancer IP: **209.38.54.117**

- **Databases**:
  - Postgres: cda6545d-b8d7-4b39-b2ad-48e6cb2b97a4
    - Host: dbr-echo-testing-postgres-do-user-15870604-0.l.db.ondigitalocean.com:25060
  - Redis: d915397f-5ab2-4173-80be-3970644ed654
    - Host: dbr-echo-testing-redis-do-user-15870604-0.l.db.ondigitalocean.com:25061

- **Storage**: dbr-echo-testing-uploads (S3 bucket)

- **Vercel Projects**:
  - echo-dashboard-testing (prj_VEa4r4YxNBPqUzOsswUuRgGANnEn)
  - echo-portal-testing (prj_5CRQIJ2PL1ggUZijPZblieEGz03Z)

### DNS Records (Added & Verified ✅)
```
A    api.echo-testing.dembrane.com        → 209.38.54.117 ✅
A    directus.echo-testing.dembrane.com   → 209.38.54.117 ✅
CNAME dashboard.echo-testing.dembrane.com → cname.vercel-dns.com (66.33.60.35, 76.76.21.98) ✅
CNAME portal.echo-testing.dembrane.com    → cname.vercel-dns.com (66.33.60.35, 76.76.21.98) ✅
```

### Credentials
- **Secrets**: Sealed and applied to echo-testing namespace

---

## Phase 2 Completion Summary

### GitOps Configuration Created ✅
- **Helm Values**: `helm/echo/values-testing.yaml`
  - imageTag: "testing" (will be updated by CI/CD)
  - Testing-specific domains (*.echo-testing.dembrane.com)
  - Resource limits optimized for testing (smaller than prod)
  - Debug mode enabled
  - All feature flags configured

- **ArgoCD Application**: `argo/echo-testing.yaml`
  - Auto-sync enabled
  - Self-heal enabled
  - Namespace: echo-testing
  - Target revision: main
  
### Kubernetes Resources Deployed ✅
```
Deployments:
- echo-api (1 replica, max 5)
- echo-directus (1 replica, max 1)
- echo-worker (1 replica, max 3)
- echo-worker-cpu (1 replica, max 2)
- echo-worker-scheduler (1 replica, max 1)
- echo-neo4j (1 replica)

Services:
- echo-api (ClusterIP:8000)
- echo-directus (ClusterIP:8055)
- echo-neo4j (ClusterIP:7474,7687)

Ingress:
- echo-ingress (nginx)
  - directus.echo-testing.dembrane.com → 209.38.54.117
  - api.echo-testing.dembrane.com → 209.38.54.117
  - SSL/TLS: echo-testing-tls (Ready ✅)

Horizontal Pod Autoscalers:
- echo-api-hpa (1-5 replicas)
- echo-directus-hpa (1 replicas)
- echo-worker-hpa (1-3 replicas)
- echo-worker-cpu-hpa (1-2 replicas)

Secrets:
- backend-secrets (31 entries) ✅
```

### Current Status
- ✅ ArgoCD application synced successfully
- ✅ All Kubernetes resources created
- ✅ Ingress configured with correct LoadBalancer IP
- ✅ SSL certificates issued and ready
- ✅ Secrets applied from Phase 1
- ⏳ Pods waiting for images (ImagePullBackOff is expected)
  - Images will be built in Phase 3 (CI/CD Pipeline)
  - Neo4j pod is running (uses public image)

### ArgoCD Access Info
- **Port-forward command**: `kubectl port-forward svc/argocd-server -n argocd 8080:443`
- **URL**: https://localhost:8080
- **Username**: admin
- **Password**: q9U4topkrRZtpU7d

### Next Steps (Phase 3)
1. Create GitHub Actions workflow for PR validation
2. Create GitHub Actions workflow for deployment
3. Set up GitHub secrets (DO_REGISTRY_TOKEN, GITOPS_PAT, SLACK_WEBHOOK_URL)
4. Build and push Docker images with "testing" tag
5. Test the complete CI/CD pipeline

---

**Document Version**: 1.2  
**Last Updated**: 2025-11-11  
**Owner**: Engineering Team  
**Status**: Phase 1 ✅ Complete | Phase 2 ✅ Complete | Phase 3 ⏳ Ready to Start
```

