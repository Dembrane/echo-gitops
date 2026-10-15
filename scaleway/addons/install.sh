#!/usr/bin/env bash
# Installs the cluster add-ons on the EU cluster, at the versions production on DigitalOcean
# runs (infra/main.tf). Repeatable: helm upgrade --install. Uses only ~/.kube/eu-prod.yaml.
set -euo pipefail
cd "$(dirname "$0")"

export KUBECONFIG="$HOME/.kube/eu-prod.yaml"
INGRESS_IP="${INGRESS_IP:-$(grep '^INGRESS_IP=' "$HOME/.config/dembrane-eu/infra.env" | cut -d= -f2)}"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --version 4.7.1 \
  -n ingress-nginx --create-namespace -f ingress-nginx-values.yaml \
  --set controller.service.loadBalancerIP="$INGRESS_IP" --wait
helm upgrade --install cert-manager jetstack/cert-manager --version 1.13.1 \
  -n cert-manager --create-namespace --set installCRDs=true --wait
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets --version 2.17.1 \
  -n kube-system --wait
helm upgrade --install argocd argo/argo-cd --version 7.8.9 \
  -n argocd --create-namespace --wait

kubectl apply -f clusterissuer.yaml
