# Setting up Authentication for the Monitoring Stack

## Basic Auth for Ingress

The monitoring stack uses Basic Auth to protect access to Prometheus and other monitoring tools. 
For security reasons, the credentials should not be stored in plaintext in the values files.

### Creating the Basic Auth Secret

1. Generate the auth string using `htpasswd`:

```bash
# Install htpasswd if not available
# On Debian/Ubuntu:
# apt-get install apache2-utils
# On MacOS:
# brew install httpd

# Generate the password
htpasswd -c auth admin
# Enter your desired password when prompted

# Get the content in the correct format
cat auth | base64
```

2. Create a Kubernetes secret manually:

```bash
kubectl create secret generic monitoring-basic-auth \
  --namespace monitoring \
  --from-file=auth=./auth
```

Alternatively, you can create a YAML file and apply it:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: monitoring-basic-auth
  namespace: monitoring
type: Opaque
data:
  auth: <BASE64_STRING_FROM_STEP_1>
```

### Using with SealedSecrets

If you're using SealedSecrets for secure secret management:

1. Create the secret as above
2. Seal it:

```bash
kubeseal --format yaml < monitoring-auth-secret.yaml > sealed-monitoring-auth.yaml
```

3. Apply the sealed secret:

```bash
kubectl apply -f sealed-monitoring-auth.yaml
```

## Grafana Admin Password

The Grafana admin password is set in the values.yaml file. For production environments, you should:

1. Set a secure password with:

```bash
helm upgrade --install monitoring ./helm/monitoring \
  --namespace monitoring \
  --set grafana.adminPassword=YOUR_SECURE_PASSWORD
```

2. Or create a values-prod.yaml file with the secure password and apply it:

```bash
helm upgrade --install monitoring ./helm/monitoring \
  --namespace monitoring \
  -f values-prod.yaml
``` 