package mailbag

import (
	"list"
	"strings"
)

// The schema for a host's context.json. Definitions only: no tasks, so it is
// checked without side effects:
//
//   cue vet -c -d '#Context' ./cue examples/example-context.json
//
// It declares exactly what the k3s deployment reads -- the k8s manifests,
// the courier config templates in configmap.yaml, the deploy scripts and the
// goss suites -- and is closed, so a key nothing reads is an
// error rather than a setting that silently does nothing. A key is required
// when some consumer prints it with no default, and optional (?) when every
// consumer supplies `| default(...)`: the default lives in the consumer, so
// the context is never a second source for it.

#Context: close({
	mta:       #Mta
	mta_ssl:   #MtaSsl
	msa:       #Msa
	imapd_ssl: #ImapdSsl
	userdb:    #Userdb
	mailboxes: #Mailboxes
	domain:    #Domain
	host_paths: #HostPaths
	services:  #Services
	image?:    close({tag?: #ImageTag})
	aliases:   #Aliases
	tls:       #Tls
	host:      #Host
	tools:     #Tools
}) & {
	// DNS-01 can answer only for names inside the zone the Route53 key may
	// write, so every name on the certificate must be in it. Kept outside the
	// close(): a comprehension inside it makes every field "not allowed".
	tls:       _
	domain:    _
	mta:       _
	msa:       _
	mta_ssl:   _
	imapd_ssl: _
	if tls.source == "cert-manager" {
		_certNamesInZone: [for n in [domain.zone, mta.dns_name, msa.dns_name, mta_ssl.dns_name, imapd_ssl.dns_name] {
			strings.HasSuffix("."+n, "."+tls.acme.route53.zone) & true
		}]
	}

	// Accounts (PROJ-040). Each rule names the offending address in its error.
	mailboxes: _
	userdb:    _
	aliases:   _
	// A mailbox in a domain the MTA does not accept can never receive mail.
	_mailboxDomainAccepted: {for m in mailboxes {
		(m): list.Contains(mta.accept_mail_for, strings.SplitN(m, "@", 2)[1]) & true
	}}
	// The build job proves the database by looking the canary up.
	_canaryIsMailbox: list.Contains(mailboxes, userdb.canary) & true
	if aliases.map != _|_ {
		for from, _ in aliases.map {
			// An alias on a mailbox shadows it entirely: courier sends
			// everything to the target and the mailbox gets nothing.
			_aliasShadowsMailbox: (from): list.Contains(mailboxes, from) & false
			// courier's "@domain" form rewrites every address in the domain,
			// so it shadows every mailbox there: allowed only for a domain
			// with no mailboxes (README.context.md, "Catch-alls").
			if strings.HasPrefix(from, "@") {
				_domainAliasShadowsMailboxes: (from): list.Contains([for m in mailboxes {"@" + strings.SplitN(m, "@", 2)[1]}], from) & false
			}
			// The alias address must be one the MTA accepts mail for.
			_aliasDomainAccepted: (from): list.Contains(mta.accept_mail_for, strings.SplitN(from, "@", 2)[1]) & true
		}
	}
}

// ---------------------------------------------------------------- scalars

#Path:     =~"^/"
#Digits:   =~"^[0-9]+$" // numbers the courier configs print verbatim
#Bool01:   "0" | "1"
#Hostname: =~"^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$"
// Lowercase only: courier compares domains case-insensitively, so requiring
// one case is what makes the exact comparisons in the account rules below
// correct (an alias "Info@x" must not slip past a mailbox "info@x").
#LocalPart: =~"^[a-z0-9][a-z0-9._+-]*$"
#Address:   =~"^[a-z0-9][a-z0-9._+-]*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$"
#Port:     int & >0 & <65536
#ImageTag: =~"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$"
#Sha256:   =~"^[0-9a-f]{64}$"

// ---------------------------------------------------------------- listeners

// Settings the esmtpd templates read for each SMTP listener, all defaulted
// there.
#Esmtpd: {
	dns_name:          #Hostname
	tls_protocol?:     string
	syslog_name?:      string
	base_syslog_name?: string
	max_daemons?:      #Digits
	max_per_ip?:       #Digits
	auth_methods?:     string
}

// Each listener embeds #Esmtpd: embedding extends the definition, where
// `#Esmtpd & {...}` would refuse every field #Esmtpd does not declare.
#Mta: {
	#Esmtpd
	accept_mail_for: [...#Hostname] & list.MinItems(1)
	dns_checks?:     #Bool01
}

#MtaSsl: {
	#Esmtpd
	dns_checks?: #Bool01
	log_dialog?: #Bool01
}

#Msa: {
	#Esmtpd
	access_file?:    #Path
	pid_file?:       #Path
	bofh_check_dns?: #Bool01
	log_level?:      #Digits
	relay_networks?: [...string]
	access_rules?: [...close({network: string, action: string})]
}

#ImapdSsl: close({dns_name: #Hostname})

// ---------------------------------------------------------------- storage and auth

// Where each volume lives on the host. The workloads mount these as hostPath
// volumes (DirectoryOrCreate) and their init containers set owner and mode,
// so nothing has to prepare the host before a deploy (PROJ-011).
#HostPaths: close({
	spool:          #Path // the shared courier spool (daemon, 0755)
	mail:           #Path // the mail store root, /vmail in the pods (root, 0755)
	courier_config: #Path // /etc/courier (daemon, 0755)
	authlib:        #Path // /etc/authlib, holding the userdb source (daemon, 0700)
})

#Userdb: close({
	// An account that must exist: the database build checks it resolves.
	canary:             #Address
	auth_modules?:      string
	auth_modules_orig?: string
	daemons?:           #Digits
	debug_login?:       #Bool01
	default_options?:   string
})

#Domain: close({
	zone: #Hostname
})

// Every mail port is declared here and nowhere else (PROJ-030), each once.
#Services: close({
	smtp_port:       #Port
	smtps_port:      #Port
	submission_port: #Port
	imaps_port:      #Port
	k8s_namespace:   =~"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"

	// A validator, so it checks only once the ports are concrete.
	_mailPorts: [smtp_port, smtps_port, submission_port, imaps_port] & list.UniqueItems()
})

// The login accounts. Each gets a userdb record (generated by the database
// build job, with its hash from /etc/mailbag/passwords) and a maildir (created
// by courierd's init container). Removing one removes the login, never the
// mail. Semantics and corner cases: README.context.md.
#Mailboxes: [...#Address] & list.MinItems(1) & list.UniqueItems()

#Aliases: close({
	// "reject" refuses mail to postmaster and the role addresses at RCPT;
	// otherwise the local part, in each hosted domain, they are delivered to
	// (aliases.template appends "@<domain>").
	postmaster: "reject" | #LocalPart
	roles?: [...#LocalPart]
	// from: to, one target each, written verbatim into courier's aliases
	// source. A key is an address, or courier's "@domain" virtual-domain form
	// (documented, not tested here). Fan-out is a forwarding sub-address,
	// never a list here.
	map?: [#Address | =~"^@([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$"]: #Address
})

// ---------------------------------------------------------------- certificates

// Where the mail certificate comes from (deploy-services.sh): a
// pre-provisioned secret, or cert-manager issuing from Let's Encrypt over
// DNS-01 in a Route53 zone. The ACME settings mean something only for
// cert-manager, so they are required there and refused for a secret.
#Tls: close({source: "secret"}) | close({source: "cert-manager", acme: #Acme})

#Acme: close({
	email: #Address // Let's Encrypt account contact
	route53: close({
		zone:           #Hostname         // the hosted zone the challenge TXT records go in
		hosted_zone_id: =~"^Z[A-Z0-9]+$" // pinned, so the key needs no zone listing
	})
})

// ---------------------------------------------------------------- host layer

#Host: close({
	k3s: close({
		version: =~"^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$"
		// The data dir belongs on the large filesystem, never the small /var
		// (PROJ-024).
		data_dir:   #Path & !~"^/var(/|$)"
		gomemlimit: =~"^[0-9]+(MiB|GiB)$"
		disable: [...string]
	})
	min_free_mb: close({
		data_dir: int & >0
		var:      int & >0
	})
})

// ---------------------------------------------------------------- tool pins

// Every tool is pinned by version and one sha256 per supported target.
#Tool: close({
	version: =~"^v?[0-9]+\\.[0-9]+\\.[0-9]+$"
	sha256: close({
		"x86_64-unknown-linux-gnu":  #Sha256
		"aarch64-unknown-linux-gnu": #Sha256
	})
})

#Tools: close({
	cue:           #Tool
	goss:          #Tool
	minijinja_cli: #Tool
})
