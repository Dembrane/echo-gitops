<div align="center">
  <!-- REMOVE THIS IF YOU DON'T HAVE A LOGO -->
   

<h3 align="center">Dembrane ECHO GitOps</h3>

  <p align="center">
    GitOps repository for deploying and managing the Dembrane ECHO platform on Kubernetes.
    <br />
     <a href="https://github.com/dembrane/echo-gitops">github.com/dembrane/echo-gitops</a>
  </p>
</div>

## Table of Contents

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#key-features">Key Features</a></li>
        <li><a href="#license">License</a></li>
      </ul>
    </li>
    <li><a href="#architecture">Architecture</a></li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#infrastructure-setup">Infrastructure Setup</a></li>
        <li><a href="#deployment">Deployment</a></li>
        <li><a href="#accessing-the-monitoring-stack">Accessing the Monitoring Stack</a></li>
      </ul>
    </li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>

## About The Project

This repository contains the Infrastructure as Code (IaC) and configuration for deploying and managing the Dembrane ECHO platform using GitOps principles. It leverages tools like Terraform, Kubernetes, Helm, and Argo CD to automate infrastructure provisioning, application deployment, and monitoring. This supplements the GitHub Actions setup <a href="https://github.com/Dembrane/echo">dembrane/echo.</a>

### Key Features

- **GitOps-Driven Deployments:** Uses Argo CD to synchronize application deployments with the state defined in the repository.
- **Automated Infrastructure Provisioning:** Employs Terraform to provision and manage cloud infrastructure resources on DigitalOcean.
- **Helm Chart Management:** Utilizes Helm charts for packaging and deploying applications to Kubernetes.
- **Comprehensive Monitoring:** Includes a monitoring stack based on Prometheus, Grafana, and Loki for collecting metrics and logs.
- **Secrets Management:** Integrates with Sealed Secrets for securely managing sensitive information.
- **Development and Production Environments:** Supports separate configurations for development and production environments.

### License

This project is licensed under the Business Source License 1.1 - see the [LICENSE](LICENSE) file for details.  A limited production use grant is available for organizations with Total Finances not exceeding EUR 1,000,000.  After three years from release date, the license will change to GNU General Public License (GPL) v3.

## Architecture

![Architecture Diagram](https://github.com/user-attachments/assets/9d5f4ab4-4fdd-40ef-83fe-43ce9c9384be)

The architecture consists of the following components:

- **DigitalOcean Kubernetes Service (DOKS):**  The Kubernetes cluster where the ECHO platform is deployed.
- **DigitalOcean Managed Databases:**  Managed PostgreSQL and Redis instances for application data and caching.
- **DigitalOcean Spaces:** Object storage for file uploads.
- **Argo CD:**  A GitOps tool that automates the deployment of applications to Kubernetes by synchronizing the cluster state with the configurations defined in this repository.
- **Helm:**  A package manager for Kubernetes, used to define, install, and upgrade applications.
- **Prometheus, Grafana, Loki:** A comprehensive monitoring stack for collecting metrics, visualizing data, and aggregating logs.
- **Sealed Secrets:**  A Kubernetes controller that allows encrypting secrets so they can be safely stored in Git.
- **Vercel:** Used for hosting the frontend dashboard and portal (dev environment only).

The repository is structured as follows:

- **`argo/`:** Contains Argo CD application definitions for deploying applications to different environments.
- **`helm/`:**  Includes Helm charts for the ECHO platform and its monitoring stack.
- **`infra/`:**  Contains Terraform configuration files for provisioning infrastructure on DigitalOcean.
- **`scripts/`:**  Scripts for querying logs from Loki.
- **`secrets/`:**  Sealed Secrets manifests for storing encrypted secrets.

## Getting Started

### Prerequisites

- **Terraform:**  Install Terraform CLI (version >= 1.0).
  ```sh
  # Example installation using Homebrew
  brew install terraform
  ```
- **Kubectl:** Install Kubectl CLI.
  ```sh
  # Example installation using Homebrew
  brew install kubectl
  ```
- **Helm:** Install Helm CLI (version >= 3.0).
  ```sh
  # Example installation using Homebrew
  brew install helm
  ```
- **DigitalOcean Account:**  A DigitalOcean account with API access.
- **Vercel Account:** A Vercel account with API access (if deploying the dev environment).
- **Sealed Secrets Controller:** Install a Sealed Secrets controller in your Kubernetes cluster.
- **kubeseal:** Install the kubeseal CLI tool.
- **doctl:** Install the DigitalOcean CLI tool.

### Infrastructure Setup

1.  **Configure Terraform Variables:**

    Fill in the required variables in `infra/terraform.tfvars` (for dev) or create a `terraform-prod.tfvars` (for prod):

    ```terraform
    do_token = ""
    spaces_access_key = ""
    spaces_secret_key = ""
    vercel_api_token = ""
    ```

    -   `do_token` - DigitalOcean token ([https://cloud.digitalocean.com/account/api/tokens](https://cloud.digitalocean.com/account/api/tokens))
    -   `spaces_access_key` - Spaces access key ([https://cloud.digitalocean.com/spaces/access_keys?i=deb664](https://cloud.digitalocean.com/spaces/access_keys?i=deb664))
    -   `spaces_secret_key` - Spaces secret key (Same as above)
    -   `vercel_api_token` - Vercel API token ([https://vercel.com/account/settings/tokens](https://vercel.com/account/settings/tokens))

2.  **Set Environment Variables:**

    Set the environment variables for the Terraform state backend:

    ```bash
    export AWS_ACCESS_KEY_ID=""
    export AWS_SECRET_ACCESS_KEY=""
    ```

    -   These should match the `spaces_access_key` and `spaces_secret_key` used above.

3.  **Apply the Infrastructure:**

    Check the comments in `main.tf`
    
4.  **Apply Argo CD Applications:**

    Deploy the Argo CD applications to synchronize the cluster state with the repository:

    ```bash
    # Example for dev
    kubectl apply -f argo/echo-dev.yaml
    kubectl apply -f argo/echo-monitoring-dev.yaml

    # Example for prod
    kubectl apply -f argo/echo-prod.yaml
    kubectl apply -f argo/echo-monitoring-prod.yaml
    ```

5.  **Configure DNS Records:**

    To get the load balancer IP, run:

    ```bash
    kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    ```

## Access k6 Web Dashboard (local)

- The k6 web dashboard is built-in and runs during a test (no database required). See docs: https://grafana.com/docs/k6/latest/results-output/web-dashboard/

Steps:

1) Start a synthetic run (dev example):
```bash
kubectl -n loadtesting create job manual-synthetic-$(date +%s) --from=cronjob/echo-k6-dev-k6-synthetic
```

2) Port-forward the k6 web dashboard:
```bash
kubectl -n loadtesting port-forward svc/echo-k6-dev-k6-webdash 5665:5665
```

3) Open http://localhost:5665 while the job is running.

Notes:
- Web dashboard stops when the test finishes. Trigger another job to view it again.
- Historical metrics are available in Grafana via Prometheus (remote write enabled).
