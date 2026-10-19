# Deploying mailbag to k3s

The raw manifests here are the only deployment path. Files ending in
`.yaml.template` are rendered against the host's `context.json` at deploy
time; `configmap.yaml` carries the courier config templates as data, which
each container renders at start.

## Prerequisites

- A single-node k3s host. Its configuration is described by `host` in
  `context.json` and checked by `goss/host-k3s.yaml`.
- `curl`, `jq`, `tar` and `xz` on the host. The renderer, goss and cue are
  fetched and checksum-verified from the pins in `context.json` on first use.
- `/etc/mailbag/context.json`, written by `generate-context.sh` at the repo
  root. It must satisfy `cue/schema.cue`.

## Steps

1. **Context.** `./generate-context.sh` (from the repo root), then edit as
   needed. Set `userdb.canary` to an account that will exist.

2. **Host preparation.** `./generate-host-scripts.sh && sudo ./prepare-host.sh`
   creates the host directories the PersistentVolumes use.

3. **Certificates** follow `tls.source`:
   - `cert-manager`: cert-manager must be installed, and
     `secret/route53-credentials` must exist in the `cert-manager` namespace
     (keys `access-key-id`, `secret-access-key`) for an IAM user with the
     policy `renderer --strict -n ../aws/cert-manager-route53-policy.json.template
     /etc/mailbag/context.json`. The deploy applies the `letsencrypt`
     ClusterIssuer (DNS-01 in `tls.acme.route53.zone`) and the Certificate.
   - `secret`: create `courier-mail-cert-tls` before deploying.
     `scripts/make-test-cert.sh` makes a CA and server certificate for a test
     host, with SANs from the context.

4. **Deploy.** `./deploy-services.sh`, or
   `IMAGE_TAG=sha-<commit> ./deploy-services.sh` for a specific build. It
   applies the namespace, configmap and storage, runs the database build job
   (which builds and validates the courier databases, including a canary
   lookup), and applies the workloads through kustomize so changed databases
   roll the pods.

5. **Mail accounts.** Add accounts to the userdb source under
   `<config.authlib_path>/userdb` on the host, then rerun `./deploy-services.sh`.

## Checking a deployment

From a checkout or the deploy tree on the host:

```bash
GOSS=$(scripts/fetch-goss.sh /etc/mailbag/context.json)
$GOSS -g goss/host-k3s.yaml --vars /etc/mailbag/context.json validate
$GOSS -g goss/smoke.yaml    --vars /etc/mailbag/context.json validate
$GOSS -g goss/certificates.yaml --vars /etc/mailbag/context.json validate
$GOSS -g goss/cert-manager.yaml --vars /etc/mailbag/context.json validate   # tls.source=cert-manager
# For a private CA (tls.source=secret), add --vars-inline '{"ca_bundle": "<ca.crt>"}'.
$GOSS -g goss/mail-delivery.yaml --vars /etc/mailbag/context.json \
  --vars-inline '{"canary_password_file": "/root/.mailbag-canary-pass"}' validate
```

Or all of it at once, deploying a tag first (`SKIP_DEPLOY=1` to test what is
running):

```bash
scripts/node-test.sh sha-<commit>
```

## Troubleshooting

```bash
kubectl get pods,svc,pvc -n mailbag
kubectl logs -n mailbag deploy/courier-mta
kubectl describe pod -n mailbag <pod>
```
