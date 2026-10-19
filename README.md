# mailbag

A self-hosted mail server -- Courier MTA, MSA, MTA-SSL and IMAP-SSL -- run as
containers on a single-node k3s cluster. Upgrades are container upgrades, not
host management.

## How it fits together

- **Context.** One file per host, `/etc/mailbag/context.json`, describes it:
  hostnames, ports, paths, certificate source, k3s settings and tool pins.
  `cue/schema.cue` is its schema; `generate-context.sh` writes a first one.
  `examples/example-context.json` is the reference.
- **Images.** CI (`.github/workflows/build-and-publish.yml`) builds them on
  every branch push. The courier packages, at the versions and source
  checksums pinned in `cue/packages.cue`, are compiled once per set of inputs
  (`scripts/packages-key.sh`), the base installs them, and each service image
  builds on the base. Images are tagged `sha-<commit>`.
- **Deployment.** `deployment/k8s/deploy-services.sh` renders the manifests
  from the context, builds and validates the courier databases in a job, and
  applies everything with kustomize. `deploy-mailbag.sh` wraps host
  preparation plus the deploy.
- **Rendering.** Templates are rendered with upstream minijinja-cli, installed
  as `renderer` and pinned in the context (`scripts/fetch-renderer.sh`). The
  courier config templates live in `deployment/k8s/configmap.yaml` and are
  rendered by each container at start.
- **Checks.** goss suites, pinned in the context (`scripts/fetch-goss.sh`):
  `goss/repo.yaml` from a checkout and in CI; `goss/host-k3s.yaml`,
  `goss/smoke.yaml`, `goss/certificates.yaml`, `goss/cert-manager.yaml` and
  `goss/mail-delivery.yaml` on a host, where `scripts/node-test.sh <tag>`
  deploys a tag and runs them. `make checks` runs the repo-level ones.
- **Work tracking.** `backlog/` (Platypus).

## Deploying to a host

```bash
./generate-context.sh                       # writes /etc/mailbag/context.json
./deploy-mailbag.sh                         # prepare the host, then deploy
IMAGE_TAG=sha-<commit> deployment/k8s/deploy-services.sh   # deploy a specific build
```
