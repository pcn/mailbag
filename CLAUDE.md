# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A self-hosted mail server built from Courier components -- MTA, MSA, MTA-SSL,
IMAP-SSL and courierd -- each in its own container on a single-node k3s
cluster. The raw manifests in `deployment/k8s/` are the only deployment path;
anything not serving that target has been removed.

## Configuration

- **Context.** One file per host, `/etc/mailbag/context.json`. Its schema is
  `cue/schema.cue` (`#Context`, closed: a key nothing reads is an error).
  Check a context with
  `"$(scripts/fetch-cue.sh <ctx>)" vet -c -d '#Context' ./cue <ctx>`.
  `generate-context.sh` writes a first one; `examples/example-context.json` is
  the reference. A key is required when a consumer prints it with no default
  and optional when every consumer supplies `| default(...)`.
- **Rendering.** Upstream minijinja-cli, installed as `renderer` (`/renderer`
  in the images), always invoked as `renderer --strict -n TEMPLATE CONTEXT`.
  `--strict` makes printing an undefined value an error. Manifests ending
  `.yaml.template` render at deploy time; the courier config templates in
  `deployment/k8s/configmap.yaml` render inside each container at start.
- **Tool pins.** cue, goss and minijinja-cli are pinned by version and a
  sha256 per target under `tools` in the context, and fetched by
  `scripts/fetch-{cue,goss,renderer}.sh`. The images take the renderer pin
  from `examples/example-context.json`.
- **Host directories** come from `host_paths` (spool, mail, courier_config,
  authlib). Workloads mount them as `hostPath` volumes with
  `DirectoryOrCreate`, and init containers set owner and mode -- there are no
  persistent volume claims and no host preparation script.
- **Ports** come from `services.*_port` everywhere -- courier config,
  containerPort, Service, probes, goss. Never write a port number elsewhere.
- **Certificates** come from `tls.source`: `cert-manager` (Let's Encrypt over
  DNS-01 in the Route53 zone `tls.acme.route53` names; every certificate name
  must be in that zone) or `secret` (a pre-provisioned `courier-mail-cert-tls`).
  The ACME account email is `letsencrypt@<domain>` on every install, by
  convention. The Route53 key is a hand-made `route53-credentials` Secret in the
  `cert-manager` namespace, for an IAM user whose policy is
  `deployment/aws/cert-manager-route53-policy.json.template` rendered against
  the context. Services read `/certs/tls.crt` and `/certs/tls.key` directly.

## Commands

```bash
make checks                      # template render check, config completeness, goss/repo.yaml
./generate-context.sh            # write /etc/mailbag/context.json
./deploy-mailbag.sh              # deploy, then show status and next steps
IMAGE_TAG=sha-<commit> deployment/k8s/deploy-services.sh   # deploy a specific build
GOSS=$(scripts/fetch-goss.sh /etc/mailbag/context.json)
$GOSS -g goss/host-k3s.yaml --vars /etc/mailbag/context.json validate   # on a host
$GOSS -g goss/smoke.yaml    --vars /etc/mailbag/context.json validate
$GOSS -g goss/certificates.yaml --vars /etc/mailbag/context.json validate
$GOSS -g goss/cert-manager.yaml --vars /etc/mailbag/context.json validate   # tls.source=cert-manager
scripts/node-test.sh sha-<commit>   # on the host: deploy that tag, then smoke, certificates,
                                    # cert-manager and mail-delivery, each reported on its own
```

Images are built by CI on every branch push and tagged `sha-<commit>`. The
courier packages image is content-addressed (`scripts/packages-key.sh`), so
the courier compile runs once per set of `Dockerfile` + `install-scripts/` +
`cue/packages.cue`. Courier versions and source sha256s are declared only in
`cue/packages.cue`; CI passes them as build args
(`cue export ./cue -e build_args --out text`) and the install scripts refuse a
download whose checksum differs. Bump a version there and nowhere else.

## Testing

Checks are goss suites: `goss/repo.yaml` from a checkout and in CI,
`goss/host-k3s.yaml` and `goss/smoke.yaml` on a host. State acceptance as goss
checks that pass, and as deliberately broken cases they must reject.
Protocols goss cannot speak (SMTP, IMAP, STARTTLS) are command checks.

## CUE

Keep every definition and decision in plain `.cue` files, where `cue vet` /
`cue export` test it without side effects. `*_tool.cue` files only
orchestrate: read the current state, feed it to a plan definition, and carry
out its writes, execs and restarts. Rules found the hard way with `cue cmd`
v0.17.1: pass the context as a tag holding its contents, not as a data input;
put guards on a task's output inside a struct field, never at the command's
top level; never guard on `len(glob.files)`; never pass a value into a
definition under the field's own name (`{x: x}` is a self-reference).

## Courier service architecture

**courierd** runs as root and privileged: it spawns delivery agents that
change credentials -- `courierlocal` (local delivery, setuid to the mail
user), `courieresmtp` (outbound SMTP), `courierdsn` (delivery status). These
deliver; they do not listen.

**Listeners**, one container each: `courier-mta` (25, inbound SMTP),
`courier-msa` (587, authenticated submission), `courier-mta-ssl` (465,
implicit TLS), `courier-imapd-ssl` (993). MTA, MSA and MTA-SSL run as daemon
(UID 1). IMAP-SSL starts as root with only the credential-changing
capabilities, because imaplogin switches to the authenticated mail user per
connection; as UID 1 it fails with "setgid: Operation not permitted" after the
banner.

**Mail flow:** listeners accept and queue into the shared spool
(`/var/spool/courier`); courierd delivers locally to `/vmail/<user>/Maildir`
or remotely; IMAP reads the maildirs. Containers communicate only through the
shared spool volume, never over the network.

**Databases** (hosteddomains, esmtpacceptmailfor, smtpaccess, aliases, userdb,
userdbshadow) are built and validated out of band by the
`courier-build-dat` job, including a canary lookup against both userdb files,
then mounted read-only from a content-hashed ConfigMap and Secret. Changing
one changes the object name and rolls the pods that mount it. Serving pods
never build databases.

**Identities:** daemon (UID 1) for the listeners and courierd's workers;
vmail (UID 300) owns mail storage and is what imaplogin and courierlocal drop
*to*; root for courierd and the privilege-dropping agents.

## Work tracking

`backlog/` (Platypus) holds the work items; follow-up work goes there, with
acceptance stated as goss checks.
