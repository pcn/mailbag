package mailbag

import "list"

// The schema for a host's context.json. Definitions only: no tasks, so it is
// checked without side effects:
//
//   cue vet -d '#Context' ./cue examples/example-context.json
//
// Closed: a key nothing reads is an error, not a silent no-op. A key is
// required when some consumer prints it with no default, and optional (?)
// when every consumer supplies `| default(...)` -- the default stays in the
// consumer, so the context is never a second source for it. Several optional
// keys are read only by the legacy systemd unit files in unit-files/.

#Context: close({
	mda:        #Mda
	mta:        #Mta
	mta_ssl:    #MtaSsl
	msa:        #Msa
	imapd_ssl:  #ImapdSsl
	userdb:     #Userdb
	domain:     #Domain
	config:     #Config
	filesystem: #Filesystem
	services:   #Services
	image?:     close({tag?: #ImageTag})
	aliases:    #Aliases
	tls:        #Tls
	host:       #Host
	tools:      #Tools
	docker?:    close({network_name: string}) // legacy systemd units
})

// ---------------------------------------------------------------- scalars

#Path:     =~"^/"
#Mode:     =~"^0[0-7]{3}$"
#Digits:   =~"^[0-9]+$"                // numbers the courier configs print verbatim
#Bool01:   "0" | "1"
#Hostname: =~"^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$"
#Address:  =~"^[^@ ]+@[a-z0-9.-]+$"
#Port:     int & >0 & <65536
#ImageTag: =~"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$"
#Sha256:   =~"^[0-9a-f]{64}$"

// ---------------------------------------------------------------- services

#Listener: {
	dns_name:      #Hostname
	tls_certfile?: #Path   // legacy systemd units; k8s reads /certs
	tls_keyfile?:  #Path
	service?:      string  // legacy systemd unit name
	tls_protocol?: string
	syslog_name?:  string
	base_syslog_name?: string
	max_daemons?:  #Digits
	max_per_ip?:   #Digits
	auth_methods?: string
}

// Each listener embeds #Listener: embedding extends the definition, where
// `#Listener & {...}` would refuse every field #Listener does not declare.
#Mta: {
	#Listener
	accept_mail_for: [...#Hostname] & list.MinItems(1)
	courierd_path_host:       #Path
	courierd_path_container?: #Path
	dns_checks?:              #Bool01
}

#MtaSsl: {
	#Listener
	accept_mail_for?:         [...#Hostname]
	courierd_path_host?:      #Path
	courierd_path_container?: #Path
	dns_checks?:              #Bool01
	log_dialog?:              #Bool01
}

#Msa: {
	#Listener
	courierd_path_host?:      #Path
	courierd_path_container?: #Path
	access_file?:     #Path
	pid_file?:        #Path
	bofh_check_dns?:  #Bool01
	log_level?:       #Digits
	relay_networks?: [...string]
	access_rules?: [...close({network: string, action: string})]
}

#ImapdSsl: #Listener

// ---------------------------------------------------------------- storage and auth

#Mda: close({
	mail_path_host:       #Path
	mail_path_container?: #Path // legacy systemd units
	owner:                #Digits
	owner_name?:          string
	mode:                 #Mode
})

#Userdb: close({
	directory: #Path
	owner:     string
	mode:      #Mode
	canary:    #Address
	auth_modules?:      string
	auth_modules_orig?: string
	daemons?:           #Digits
	debug_login?:       #Bool01
	default_options?:   string
})

#Domain: close({
	name: string
	zone: #Hostname
})

#Config: close({
	courier_path: #Path
	courier_mode: #Mode
	authlib_path: #Path
	authlib_mode: #Mode
})

#Filesystem: close({
	base_storage_mode: #Mode
	msgq_mode:         #Mode
	msgs_mode:         #Mode
	filters_mode:      #Mode
	allfilters_mode:   #Mode
	tmp_mode:          #Mode
	track_mode:        #Mode
})

// Every mail port is declared here and nowhere else (PROJ-030), each once.
#Services: close({
	smtp_port:       #Port
	smtps_port:      #Port
	submission_port: #Port
	imaps_port:      #Port
	ssh_port?:       #Port
	k8s_namespace?:  string
	k8s_services?: [...string]
	k8s_pods?: [...string]

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

// Where the mail certificate comes from (deploy-services.sh). An issuer means
// something only for cert-manager, so it is required there and refused for a
// pre-provisioned secret.
#Tls: close({source: "secret"}) | close({source: "cert-manager", issuer: string & !=""})

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
