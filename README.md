# mailbag

A self-hosted mail server -- Courier MTA, MSA, MTA-SSL and IMAP-SSL -- run as
containers on a single-node k3s cluster. Upgrades are container upgrades, not
host management.

## How it fits together

- **Context.** One file per host, `/etc/mailbag/context.json`, describes it:
  hostnames, ports, paths, certificate source, k3s settings and tool pins.
  `cue/schema.cue` is its schema; `generate-context.sh` writes a first one.
  `examples/example-context.json` is the reference.
- **Host layer.** k3s itself and its host configuration (`config.yaml`, the
  GOMEMLIMIT drop-in, `K3S_DATA_DIR` in `/etc/environment`) come from
  `host.k3s` in the context, applied by `cue cmd plan / apply / verify`
  (`cue/host_tool.cue`). When `tls.source` is `cert-manager`, the same apply
  installs cert-manager from its static release manifest, pinned by version
  and sha256 in `host.cert_manager` and checked before anything is applied;
  an upgrade is a bump of both values. It also caps log growth on `/var`
  from `host.logs`: a journald drop-in and the logrotate rule for rsyslog's
  logs. Every decision is in `cue/plan.cue`,
  tested by `cue/plan_tests.cue`.
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

## Setting up a host

On a Debian host, as root, from a checkout, with the context in place
(`./generate-context.sh`). `scripts/fetch-cue.sh` downloads the cue pinned in
the context and checks its sha256; that is the one bootstrap step.

```bash
CUE=$(scripts/fetch-cue.sh /etc/mailbag/context.json)
"$CUE" cmd -t ctx="$(cat /etc/mailbag/context.json)" plan  ./cue   # show what apply would change
"$CUE" cmd -t ctx="$(cat /etc/mailbag/context.json)" apply ./cue   # converge
"$CUE" cmd verify ./cue                                            # goss/host-k3s.yaml
```

`apply` writes only files that differ, restarts k3s only when its config or
drop-in changed (the mail pods keep running), and installs k3s from upstream's
`install.sh`, pinned by version and sha256, only when it is missing or at
another version. On a host whose k3s data is still under
`/var/lib/rancher/k3s`, `plan` and `apply` refuse and print the manual
migration steps.

## Deploying to a host

```bash
./generate-context.sh                       # writes /etc/mailbag/context.json
./deploy-mailbag.sh                         # deploy, then show status and next steps
IMAGE_TAG=sha-<commit> deployment/k8s/deploy-services.sh   # deploy a specific build
```
