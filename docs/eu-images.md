# Images for the EU cluster

The EU cluster pulls `rg.fr-par.scw.cloud/<namespace>/dembrane-web-{api,worker,media,web,migrate}:<sha>`,
where `<sha>` is the Dembrane/echo main commit in `global.imageTag` of
`helm/dembrane-web/values-eu-prod.yaml`. The images hold no environment: hosts, models and
switches are read at start from the values, so the same image runs in both productions.

## How echo builds them today

`.github/workflows/platform.yml` runs `.github/scripts/build-images.sh --push` with
`REGISTRY`, `IMAGE_PREFIX` and `TAG` set. It tags every image `<prefix><app>:<sha>` and
`src-<key>` (a hash of the files that go into it), and reuses an image whose key is already in
the registry.

- Pull requests and staging push to Google Artifact Registry, without the prefix.
- A release tag `vX.Y.Z` on main (job `70-deploy-prod`, after the prod approval) pushes to
  `registry.digitalocean.com/dbr-cr` as `dembrane-web-<app>:<sha>` and bumps
  `global.imageTag` in `values-prod.yaml` of echo-gitops.

So the DigitalOcean registry holds an image for a main commit only if that commit was
released. For any other commit use the build option below.

## Today: copy from the DigitalOcean registry (a released commit)

Needs the DigitalOcean registry token (read) and a Scaleway secret key. The copy keeps the
manifest digests, so what runs in the EU is byte-identical to what was released.

```sh
SHA=<40 character commit of a release>
NS=<scaleway registry namespace>
skopeo login registry.digitalocean.com -u "$DO_REGISTRY_TOKEN" -p "$DO_REGISTRY_TOKEN"
skopeo login rg.fr-par.scw.cloud -u nologin -p "$SCW_SECRET_KEY"
for app in api worker media web migrate; do
  skopeo copy --all --preserve-digests \
    docker://registry.digitalocean.com/dbr-cr/dembrane-web-$app:$SHA \
    docker://rg.fr-par.scw.cloud/$NS/dembrane-web-$app:$SHA
done
```

`crane copy registry.digitalocean.com/dbr-cr/dembrane-web-$app:$SHA rg.fr-par.scw.cloud/$NS/dembrane-web-$app:$SHA`
does the same. Check afterwards that all five tags exist:
`skopeo inspect docker://rg.fr-par.scw.cloud/$NS/dembrane-web-$app:$SHA`.

Then set `global.registry` and `global.imageTag` in `values-eu-prod.yaml` and commit it.
The registry namespace must be private, with the pull secret `scw-registry-secret`
(`secrets/dembrane-web-eu-secrets.keys.md`).

## A commit that was not released: build into Scaleway

From a clean checkout of Dembrane/echo at the commit, with Docker and Buildx:

```sh
docker login rg.fr-par.scw.cloud -u nologin -p "$SCW_SECRET_KEY"
REGISTRY=rg.fr-par.scw.cloud/$NS IMAGE_PREFIX=dembrane-web- TAG=$SHA \
  .github/scripts/build-images.sh --push
```

## Later: CI

Add a job `75-deploy-eu` to `platform.yml`, next to `70-deploy-prod`, with its own protected
environment `eu-prod` (required reviewers) so the EU is released on purpose, not with every
production release:

1. Log in with `docker/login-action` to `rg.fr-par.scw.cloud`, user `nologin`, password the
   repository secret `SCW_REGISTRY_KEY`. Scaleway has no GitHub sign-in federation, so this is a
   stored key: an IAM application limited to the registry namespace (read and write), with an
   expiry, rotated before it ends.
2. Run `build-images.sh --push` with `REGISTRY=rg.fr-par.scw.cloud/<namespace>`,
   `IMAGE_PREFIX=dembrane-web-` and `TAG` the release sha. It reuses any `src-` image already
   there, so a release that changes nothing for an app costs a manifest copy.
3. Bump the tag: `gitops-bump.sh` takes `prod` and edits `values-prod.yaml`. Add an `eu` case
   that sets `file=helm/dembrane-web/values-eu-prod.yaml`, and call it with branch `scaleway`
   (`vars.GITOPS_EU_BRANCH`). It edits the one `imageTag:` line under `global:`, so the
   placeholder line is replaced as is.
4. Keep automated sync off on the EU Application until the guard rails exist; the bump then
   waits for a person to sync.

Until the job exists, step 1 of "Today" is the whole process.
