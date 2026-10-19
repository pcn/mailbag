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
// prepare-host, the courier config templates in configmap.yaml, the deploy
// scripts and the goss suites -- and is closed, so a key nothing reads is an
// error rather than a setting that silently does nothing. A key is required
// when some consumer prints it with no default, and optional (?) when every
// consumer supplies `| default(...)`: the default lives in the consumer, so
// the context is never a second source for it.

#Context: close({
	mda:       #Mda
	mta:       #Mta
	mta_ssl:   #MtaSsl
	msa:       #Msa
	imapd_ssl: #ImapdSsl
	userdb:    #Userdb
	domain:    #Domain
	config:    #Config
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
}

// ---------------------------------------------------------------- scalars

#Path:     =~"^/"
#Digits:   =~"^[0-9]+$" // numbers the courier configs print verbatim
#Bool01:   "0" | "1"
#Hostname: =~"^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$"
#Address:  =~"^[^@ ]+@[a-z0-9.-]+$"
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
	// Host path of the shared courier spool (prepare-host).
	courierd_path_host: #Path
	dns_checks?:        #Bool01
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

#Mda: close({
	// Host path of the mail store (prepare-host).
	mail_path_host: #Path
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

// Host paths of the courier and authlib config volumes (prepare-host).
#Config: close({
	courier_path: #Path
	authlib_path: #Path
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

#Aliases: close({
	// "reject" refuses mail to postmaster and the role addresses; otherwise
	// the address they are delivered to.
	postmaster: "reject" | #Address
	roles?: [...string]
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
