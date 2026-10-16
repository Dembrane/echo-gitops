# echo-gitops

What runs on dembrane's production Kubernetes cluster on DigitalOcean
(`dbr-echo-prod-k8s-cluster`, ams3), as Helm charts that Argo CD syncs from this repository.
Images are built by [Dembrane/echo](https://github.com/Dembrane/echo) and pushed to
`registry.digitalocean.com/dbr-cr`. Staging and PR previews of dembrane v3 run on GCP Cloud Run
and are deployed from Dembrane/echo, not from here.

Production is moving from the old stack to dembrane v3. Until [CUTOVER.md](CUTOVER.md) is done,
both are in this repository and the old one serves customers.

## Layout

- `helm/dembrane-web/`: dembrane v3 (`dembrane/platform` in Dembrane/echo). API, worker, media
  (ffmpeg), dashboard and portal, the migrate job as an Argo CD PreSync hook, a PostSync smoke
  check, and the ingress for `api`, `dashboard` and `portal.dembrane.com`. Values:
  `values-prod.yaml`.
- `helm/echo/`: **legacy**, the old stack (Python API, Dramatiq workers, Directus, Neo4j), still
  live in namespace `echo-prod` until the cutover, and its rollback after. Values:
  `values-prod.yaml` and `values-extended-env.yaml`. It also owns the cluster-scoped ClusterIssuer
  `letsencrypt-prod` and the `echo-*` PriorityClasses (CUTOVER.md, "Release the contract").
- `helm/monitoring/`: Prometheus, Grafana, Loki, Promtail and blackbox probes in namespace
  `monitoring`. Values: `values-prod.yaml` over `values.yaml`.
- `argo/`: the Argo CD Applications: `dembrane-web-prod` (v3, manual sync until the cutover),
  `echo-prod` (legacy, automated), `echo-monitoring-prod`.
- `secrets/`: SealedSecrets, applied by hand. `dembrane-web-prod-secrets.keys.md` lists v3's keys
  and where each value comes from.
- `secret-manager.sh`: edit, compare and seal the plaintext secret files (`prod` is the old
  stack's `echo-backend-secrets`, `web-prod` is v3's `dembrane-web-prod-secrets`).
- `infra/`: Terraform for the DigitalOcean resources under the cluster: VPC, the DOKS cluster,
  managed Postgres, Valkey, the Spaces bucket, the registry, and the cluster add-ons
  (ingress-nginx, cert-manager, sealed-secrets, Argo CD, metrics-server, the DO CSI driver).
  Workspace `prod` describes the live production resources.
- `ai-infra/`: Terraform for a GCP state bucket, a Vertex AI endpoint and a service account with
  `roles/aiplatform.user`. Kept until it is confirmed whether that account is the one behind the
  old stack's `GCP_SA_JSON`.
- `scripts/`: Loki log queries (`query_logs.py`), rebuilding the old stack's plaintext secret
  file from the cluster (`reconstruct-secrets.py`), and a k6 load test of the portal's upload
  flow.

## How a release reaches production

Dembrane/echo's `platform` workflow, job `70-deploy-prod`, runs on a `vX.Y.Z` tag after the
`prod` environment's approval. It pushes the five images as
`registry.digitalocean.com/dbr-cr/dembrane-web-{api,worker,media,web,migrate}:<commit sha>` and
commits that sha to `global.imageTag` in `helm/dembrane-web/values-prod.yaml` on the branch the
app tracks (`prod-v3` until the cutover, `main` after). Argo CD then syncs: the migrate hook,
then the rollout, then the smoke hook. A failed migration or smoke check fails the sync and
leaves the previous release running.

Before the cutover the app syncs only when someone runs `argocd app sync dembrane-web-prod`.

## Argo CD Applications are registered by hand

Argo CD reads the charts from this repository, but the Application objects themselves are not
reconciled from `argo/`: each one is created with `kubectl apply -f argo/<file>` and a later
edit to the file changes nothing until it is applied again. Compare with
`kubectl -n argocd get application <name> -o yaml` before trusting the file.

## Secrets

Plaintext secret files never enter git (`secrets/.gitignore`). To change one:

```sh
./secret-manager.sh web-prod update        # or: batch <file>, list, get <KEY>
./secret-manager.sh web-prod seal          # kubeseal with the prod cluster's key
kubectl apply -f secrets/sealed-dembrane-web-prod-secrets.yaml
```

Pods read a changed secret only when they restart: run a sync, or
`kubectl -n dembrane-web-prod rollout restart deployment`.

## Validate a chart change

```sh
helm lint helm/dembrane-web -f helm/dembrane-web/values-prod.yaml
helm template dembrane-web-prod helm/dembrane-web -f helm/dembrane-web/values-prod.yaml -n dembrane-web-prod
```

## License

Business Source License 1.1, see [LICENSE](LICENSE).
