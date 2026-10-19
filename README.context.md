# The context.json file

`/etc/mailbag/context.json` is the one description of a host: hostnames,
ports, paths, the certificate source, the k3s settings, and the pinned tool
versions. The deploy scripts and the renderer read it, each container renders
its courier config from it, and the goss suites take their values from it.

`cue/schema.cue` defines what it may contain (`#Context`). It is closed, so a
key nothing reads is rejected rather than silently ignored.
`examples/example-context.json` is a complete example; `generate-context.sh`
writes a first one for a new host.

## Mailboxes and aliases

Mailboxes and aliases are declared in the context (PROJ-040). Nothing below
about the catch-all is implemented or tested by this repo: alias entries are
handed to courier as written, and courier's behaviour is what is described.

### Shape

```json
"mailboxes": ["testuser@example.org", "letsencrypt@example.org"],
"aliases": {
  "postmaster": "reject",
  "roles": ["abuse", "root"],
  "map": {
    "info@example.org": "testuser@example.org",
    "@trap.example.org": "trapuser"
  }
}
```

- **mailboxes** are login accounts with a maildir, lowercase addresses in a
  domain listed in `mta.accept_mail_for`; `userdb.canary` must be one.
  Password hashes are not in the context; they live in
  `/etc/mailbag/passwords` (root, 0600), set with
  `scripts/mailbox-passwd.sh <address>` (prompts) or `--random <file>|-`.
- **Derived, never hand-edited:** the database build job generates the
  userdb source from `mailboxes` and the hashes (uid/gid 300, home
  `/vmail/<domain>/<user>`), and refuses to build if a mailbox has no hash or
  a hash names no mailbox. courierd's init container creates each missing
  maildir (vmail, 0700). Then redeploy: `deployment/k8s/deploy-services.sh`.
- **Removing a mailbox keeps its mail.** The login goes; the maildir stays,
  and `scripts/mailbox-orphans.sh` (also printed by `scripts/node-test.sh`)
  lists such orphans. Nothing deletes mail.
- **aliases.map** is `from: to`, one target each. Each entry is written
  verbatim, after the postmaster and role entries, into courier's aliases
  source, which `makealiases` compiles; courier's semantics apply.
- **No multi-target aliases.** To fan out, use a sub-address whose
  `.courier-<ext>` file forwards to several addresses (see below), so the
  aliases map stays one-to-one.

### postmaster and the role addresses

- `"reject"`: no role aliases are emitted. Mail to postmaster@, abuse@,
  root@, mailer-daemon@ and uucp@ in every hosted domain is refused at RCPT
  with 550 -- nothing is accepted, stored or bounced, so no backscatter.
- Otherwise the value is a **local part** (the schema refuses a full
  address), and the template writes `postmaster@<d>: <value>@<d>` for every
  domain in `mta.accept_mail_for`, with each role pointing at postmaster@<d>.
- `roles` replaces the default list (abuse, root, mailer-daemon,
  MAILER-DAEMON, uucp); it has no effect with `"reject"`.

### Corner cases of aliases (courier semantics)

1. **An alias on an existing mailbox shadows it.** If `from` is a mailbox,
   that mailbox never receives mail again; everything goes to `to`. With one
   target per alias this is a pure redirect, so the schema refuses an alias
   key that is also a declared mailbox (and, for the same reason, any
   uppercase address: courier compares case-insensitively).
2. **Aliases chain.** A target that is itself an alias is expanded when the
   database is built. Avoid loops; the build does not promise to detect them.
3. **Remote targets forward.** A target outside the hosted domains is
   forwarded out through courieresmtp, so it needs outbound port 25 and the
   receiving side's SPF policy will see this host as the sender's relay.
4. **Bounces.** A single-target alias does not change delivery status
   notifications: a failed delivery bounces to the sender as usual. (Courier
   treats multi-target aliases as private lists and sends no bounces for them
   -- one more reason they are not allowed here.)
5. **Sub-addresses come before any catch-all.** For `user-ext@dom`, courier
   first tries the exact address, then splits at `-` (up to three times) and
   delivers to `user` with extension `ext`, via `user`'s `.courier-ext`, or
   `.courier-default` if there is none. So if `a` is a mailbox and `a-b` is
   not, `a-b@dom` belongs to `a`. A mailbox whose name contains `-` still
   matches exactly first.
6. **Fan-out through a sub-address.** `team-all@dom` with
   `<home of team>/.courier-all` listing several addresses delivers a copy to
   each; this is the supported replacement for multi-target aliases.

### Catch-alls: two courier mechanisms, very different

**`@domain: user` in the aliases map (courier "virtual domain").** Courier
rewrites *every* address `foo@domain` to `user-foo@<me>` and delivers via
`user`'s `.courier-foo` or `.courier-default`. Consequences here:

- It captures the whole domain, **including declared mailboxes** -- none of
  them would receive mail any more -- so the schema allows it only for a
  domain with no mailboxes, e.g. a dedicated `trap.example.org` for a spam
  trap.
- `<me>` is courier's own hostname. These containers have no
  `/etc/courier/me`, so it is the **pod name** (`courierd-<hash>`), which is
  in no hosted domain: as deployed today the rewritten mail would be
  undeliverable. Using this form needs `me` set to a hosted domain first.
- It is not recursive: other aliases pointing into the domain are not
  re-expanded through it.
- The domain must be in `mta.accept_mail_for`, or the MTA refuses it at RCPT.

**A mailbox named `alias@domain` (courier local delivery).** When neither the
exact address nor any `user-ext` split matches an account, courier looks up
an account literally named `alias@<domain>` and delivers to it with the
original local part as the extension (courier 2.0.8,
`courier/module.local/local.C`, the `lai.address="alias"` lookup). So:

- Declared mailboxes and their sub-addresses keep precedence; only unknown
  addresses reach the catch-all. This is the behaviour a catch-all next to
  real mailboxes needs, and it needs no new syntax: declare `alias@domain` in
  `mailboxes`.
- Every address in the domain is then accepted at RCPT, so the domain draws
  the full spam load -- which is the point for a trap, and a cost otherwise.
- Delivery uses `alias`'s `.courier-<localpart>` or `.courier-default`.
  Whether mail with neither lands in its Maildir is not verified.
