# AI Infra quickstart (europe-west4)

Minimal steps for a teammate to use the shared GCP SA from ArgoCD and run Terraform locally.

## 1) Fetch creds from ArgoCD and write to a temp file
```bash
kubectl -n argocd get secret gcp-sa -o json \
  | jq -r '.data["application-credentials.json"]' \
  | base64 --decode > /tmp/gcp-sa.json

export GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp-sa.json
```

## 2) Run Terraform (remote state already bootstrapped)
```bash
# Vertex stack (state backend is GCS; pass your bucket name)
cd ai-infra/vertex
terraform init -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="prefix=vertex"
terraform apply -auto-approve \
  -var "project_id=$PROJECT_ID" \
  -var "region=europe-west4" \
  -var "location=europe-west4" \
  -var "endpoint_display_name=echo-ai-endpoint"
```

## 3) Cleanup temporary creds
```bash
rm -f /tmp/gcp-sa.json
unset GOOGLE_APPLICATION_CREDENTIALS
```

Notes:
- Gemini models are publisher models; call them directly: gemini-2.5-pro, gemini-2.0-flash, gemini-2.0-flash-lite.
