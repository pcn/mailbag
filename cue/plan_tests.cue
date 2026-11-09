package mailbag

import (
	"encoding/json"
	"list"
	"strings"
)

// Test cases for #Plan (PROJ-026, PROJ-027), run by goss/repo.yaml:
//
//   cue export ./cue -e tests > /dev/null
//
// Each case starts from a host already in sync, overrides only the inputs it
// is about, and compares every field of #Plan's result with its expectation:
// an extra write, restart or install fails as surely as a missing one.

_testHost: #Host & {
	k3s: {
		version:        "v1.32.5+k3s1"
		install_sha256: "d75e014f2d2ab5d30a318efa5c326f3b0b7596f194afcff90fa7a7a91166d5f7"
		data_dir:       "/home/k3s"
		gomemlimit:     "300MiB"
		disable: ["traefik", "metrics-server", "local-storage"]
	}
	// A placeholder checksum: the real pin lives only in the example context
	// (PROJ-027), and these tests never fetch anything.
	cert_manager: {
		version:         "v1.21.2"
		manifest_sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	}
	logs: {
		journald: {system_max_use: "100M", system_max_file_size: "20M", max_retention: "1month"}
		rsyslog: {frequency: "daily", rotate: 4, maxsize: "50M"}
	}
	min_free_mb: {data_dir: 2048, var: 1024}
}

// farout's hand-made log limits before host setup managed them (PROJ-044):
// the values match the context, but not the generated text.
_faroutJournald: """
	# /var is a 2.8G partition shared with k3s data; the 10%-of-filesystem default
	# let the journal reach 284M. Cap it explicitly.
	[Journal]
	SystemMaxUse=100M
	SystemMaxFileSize=20M
	MaxRetentionSec=1month

	"""
_faroutLogrotate: """
	/var/log/syslog
	/var/log/mail.log
	/var/log/kern.log
	/var/log/auth.log
	/var/log/user.log
	/var/log/cron.log
	{
	\trotate 4
	\tdaily
	\tmaxsize 50M
	\tmissingok
	\tnotifempty
	\tcompress
	\tsharedscripts
	\tpostrotate
	\t\t/usr/lib/rsyslog/rsyslog-rotate
	\tendscript
	}

	"""

// Markers for the script's steps, for order checks.
_step: {
	verifyCertManager: "\"$t/cert-manager.yaml\" | sha256sum -c -"
	restartK3s:        "systemctl restart k3s"
	installK3s:        "INSTALL_K3S_VERSION="
	applyCertManager:  "kubectl apply --server-side"
}

let _want = #Desired & {in: _testHost}

#Expect: close({
	mkdirs: [...string]
	writes: [...string] // paths, in order
	daemonReload:       bool
	restartK3s:         bool
	installK3s:         bool
	refuse:             bool
	installCertManager: bool
	restartJournald:    bool
	// When given, the exact /etc/environment text written.
	env?: string
	// When given, these script steps (_step values) appear in this order.
	order?: [...string]
})

#Case: {
	have: {
		config:           *_want.config | string
		dropin:           *_want.dropin | string
		env:              *"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin\nK3S_DATA_DIR=/home/k3s\n" | string
		k3sVersion:       *"k3s version v1.32.5+k3s1 (8e8f2a47)\ngo version go1.23.8\n" | string
		oldDataDir:       *false | bool
		certManagerImage: *"quay.io/jetstack/cert-manager-controller:v1.21.2" | string
		journald:         *_want.journald | string
		logrotate:        *_want.logrotate | string
	}
	tlsSource: *"cert-manager" | "secret"
	want:      #Expect

	let h = have
	let s = tlsSource
	let p = #Plan & {host: _testHost, tlsSource: s, have: h}
	got: #Expect & {
		mkdirs: p.mkdirs
		writes: [for w in p.writes {w.path}]
		daemonReload:       p.daemonReload
		restartK3s:         p.restartK3s
		installK3s:         p.installK3s
		refuse:             p.refuse
		installCertManager: p.installCertManager
		restartJournald:    p.restartJournald
		if want.env != _|_ {
			env: [for w in p.writes if w.path == #Paths.env {w.contents}][0]
		}
		if want.order != _|_ {
			// Each step present, and their first occurrences ascending.
			let at = [for m in want.order {strings.Index(p.script, m)}]
			_present: [for i in at {i >= 0 & true}]
			_ordered: list.IsSorted(at, list.Ascending) & true
			order:    want.order
		}
	}
	// Every field, compared with defaults resolved. Unifying got with want
	// would not do: want's fields are defaults (*false | bool), which accept
	// any bool, so an unexpected restart or install would pass.
	_match: {for k, v in got {(k): (json.Marshal(v) == json.Marshal(want[k])) & true}}
}

// Nothing to do. Defaults, so a case overrides only what it expects to happen.
let _none = {
	mkdirs: *[] | [...string]
	writes: *[] | [...string]
	daemonReload:       *false | bool
	restartK3s:         *false | bool
	installK3s:         *false | bool
	refuse:             *false | bool
	installCertManager: *false | bool
	restartJournald:    *false | bool
}

tests: [string]: #Case
tests: {
	inSync: {
		want: _none
	}
	missingDropin: {
		have: dropin: ""
		want: _none & {
			mkdirs: [#Paths.dropinDir]
			writes: [#Paths.dropin]
			daemonReload: true
			restartK3s:   true
		}
	}
	handEditedDropin: {
		have: dropin: "[Service]\nEnvironment=GOMEMLIMIT=1GiB\n"
		want: _none & {
			mkdirs: [#Paths.dropinDir]
			writes: [#Paths.dropin]
			daemonReload: true
			restartK3s:   true
		}
	}
	handEditedConfig: {
		have: config: "data-dir: /home/k3s\n"
		want: _none & {
			mkdirs: [#Paths.configDir]
			writes: [#Paths.config]
			restartK3s: true
		}
	}
	staleEnvLineReplacedInPlace: {
		have: env: "PATH=/usr/bin\nK3S_DATA_DIR=/var/lib/rancher/k3s\nEDITOR=vi\n"
		want: _none & {
			writes: [#Paths.env]
			env: "PATH=/usr/bin\nK3S_DATA_DIR=/home/k3s\nEDITOR=vi\n"
		}
	}
	unrelatedLineAfterOurs: {
		have: env: "K3S_DATA_DIR=/home/k3s\nEDITOR=vi\n"
		want: _none
	}
	missingEnvironmentFile: {
		have: env: ""
		want: _none & {
			writes: [#Paths.env]
			env: "K3S_DATA_DIR=/home/k3s\n"
		}
	}
	freshHost: {
		have: {config: "", dropin: "", env: "", k3sVersion: "", certManagerImage: ""}
		// install.sh reloads systemd and starts k3s itself. The manifest is
		// checked before k3s is installed, and applied after.
		want: _none & {
			mkdirs: [#Paths.configDir, #Paths.dropinDir]
			writes: [#Paths.config, #Paths.dropin, #Paths.env]
			installK3s:         true
			installCertManager: true
			order: [_step.verifyCertManager, _step.installK3s, _step.applyCertManager]
		}
	}
	versionDrift: {
		have: k3sVersion: "k3s version v1.31.9+k3s1 (abcdef12)\n"
		want: _none & {installK3s: true}
	}
	oldDataDirRefused: {
		// Even with every file wrong, nothing is planned but the refusal.
		have: {config: "", dropin: "", env: "", k3sVersion: "", oldDataDir: true, certManagerImage: "", journald: "", logrotate: ""}
		want: _none & {refuse: true}
	}

	// Log limits (PROJ-044).
	faroutHandMadeJournald: {
		have: journald: _faroutJournald
		want: _none & {
			mkdirs: [#Paths.journaldDir]
			writes: [#Paths.journald]
			restartJournald: true
		}
	}
	missingJournald: {
		have: journald: ""
		want: _none & {
			mkdirs: [#Paths.journaldDir]
			writes: [#Paths.journald]
			restartJournald: true
		}
	}
	// logrotate reads its rules at each run: a rewrite restarts nothing.
	faroutHandEditedLogrotate: {
		have: logrotate: _faroutLogrotate
		want: _none & {
			mkdirs: [#Paths.logrotateDir]
			writes: [#Paths.logrotate]
		}
	}
	missingLogrotate: {
		have: logrotate: ""
		want: _none & {
			mkdirs: [#Paths.logrotateDir]
			writes: [#Paths.logrotate]
		}
	}

	// cert-manager (PROJ-027).
	certManagerMissing: {
		have: certManagerImage: ""
		want: _none & {
			installCertManager: true
			order: [_step.verifyCertManager, _step.applyCertManager]
		}
	}
	certManagerOtherVersion: {
		have: certManagerImage: "quay.io/jetstack/cert-manager-controller:v1.20.5"
		want: _none & {installCertManager: true}
	}
	certManagerNotNeededForSecret: {
		tlsSource: "secret"
		have: certManagerImage: ""
		want: _none
	}
	certManagerAfterK3sRestart: {
		have: {config: "data-dir: /home/k3s\n", certManagerImage: ""}
		want: _none & {
			mkdirs: [#Paths.configDir]
			writes: [#Paths.config]
			restartK3s:         true
			installCertManager: true
			order: [_step.verifyCertManager, _step.restartK3s, _step.applyCertManager]
		}
	}
}
