<div align="center">
  <!-- REMOVE THIS IF YOU DON'T HAVE A LOGO -->
    <img src="https://github.com/user-attachments/assets/9d5f4ab4-4fdd-40ef-83fe-43ce9c9384be" height="400">

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

This repository contains the Infrastructure as Code (IaC) and configuration for deploying and managing the Dembrane ECHO platform using GitOps principles. It leverages tools like Terraform, Kubernetes, Helm, and Argo CD to automate infrastructure provisioning, application deployment, and monitoring.

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

![Architecture Diagram](https://github.com/user-attachments/assets/721b7fb3-e480-4809-9023-fd48b82b1f8c)

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

    Initialize and apply the Terraform configuration:

    ```bash
    terraform init
    terraform apply -var-file=./terraform.tfvars # or terraform-prod.tfvars
    ```

4.  **Get the Outputs:**

    Retrieve the outputs from Terraform:

    ```bash
    terraform output -json
    ```

### Deployment

1.  **Configure Kubernetes Credentials:**

    Configure `kubectl` to connect to your DigitalOcean Kubernetes cluster. The `infra/main.tf` file automates the creation of the cluster but you will need to manually save the kubeconfig:

    ```bash
    doctl kubernetes cluster kubeconfig save dbr-echo-<env>-k8s-cluster
    ```

    Replace `<env>` with `dev` or `prod`.

2.  **Create Secrets:**

    Create the necessary secrets for the backend and monitoring components.  Update the secrets files in the `secrets/` directory with your actual values.  Then seal the secrets:

    ```bash
    # Backend Secrets (example for dev)
    kubeseal --context=do-ams3-dbr-echo-dev-k8s-cluster \
      --controller-namespace=kube-system \
      --controller-name=sealed-secrets \
      < secrets/backend-secrets-dev.yaml > secrets/sealed-backend-secrets-dev.yaml
    kubectl apply -f secrets/sealed-backend-secrets-dev.yaml

    # Monitoring Secrets (example for dev)
    kubeseal --context=do-ams3-dbr-echo-dev-k8s-cluster \
      --controller-namespace=kube-system \
      --controller-name=sealed-secrets \
      < secrets/monitoring-secrets-dev.yaml > secrets/sealed-monitoring-secrets-dev.yaml
    kubectl apply -f secrets/sealed-monitoring-secrets-dev.yaml
    ```

    Repeat for the production environment, replacing `dev` with `prod` and using the appropriate cluster context.

3.  **Apply Argo CD Applications:**

    Deploy the Argo CD applications to synchronize the cluster state with the repository:

    ```bash
    # Example for dev
    kubectl apply -f argo/echo-dev.yaml
    kubectl apply -f argo/echo-monitoring-dev.yaml

    # Example for prod
    kubectl apply -f argo/echo-prod.yaml
    kubectl apply -f argo/echo-monitoring-prod.yaml
    ```

4.  **Configure DNS Records:**

    Configure DNS records for the monitoring services:

    -   Development:

        ```
        grafana-echo-dev.echo-next.dembrane.com    → DigitalOcean Load Balancer IP
        prometheus-echo-dev.echo-next.dembrane.com → DigitalOcean Load Balancer IP
        ```

    -   Production:

        ```
        grafana-echo-prod.dembrane.com    → DigitalOcean Load Balancer IP
        prometheus-echo-prod.dembrane.com → DigitalOcean Load Balancer IP
        ```

    To get the load balancer IP, run:

    ```bash
    kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    ```

### Accessing the Monitoring Stack

#### Grafana

-   URL (Development): <https://grafana-echo-dev.echo-next.dembrane.com>
-   URL (Production): <https://grafana-echo-prod.dembrane.com>

    Default login credentials:

    -   Username: `admin`
    -   Password: Defined in `secrets/monitoring-secrets-dev.yaml` or `secrets/monitoring-secrets-prod.yaml`

#### Prometheus

-   URL (Development): <https://prometheus-echo-dev.echo-next.dembrane.com>
-   URL (Production): <https://prometheus-echo-prod.dembrane.com>

## Acknowledgments

-   This README was created using [gitreadme.dev](https://gitreadme.dev) — an AI tool that looks at your entire codebase to instantly generate high-quality README files.
