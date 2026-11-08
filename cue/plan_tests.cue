package mailbag

// Test cases for #Plan (PROJ-026), run by goss/repo.yaml:
//
//   cue export ./cue -e tests > /dev/null
//
// Each case starts from a host already in sync, overrides only the inputs it
// is about, and unifies #Plan's result with a closed expectation: an extra
// write, restart or install conflicts as surely as a missing one.

_testHost: #Host & {
	k3s: {
		version:        "v1.32.5+k3s1"
		install_sha256: "d75e014f2d2ab5d30a318efa5c326f3b0b7596f194afcff90fa7a7a91166d5f7"
		data_dir:       "/home/k3s"
		gomemlimit:     "300MiB"
		disable: ["traefik", "metrics-server", "local-storage"]
	}
	min_free_mb: {data_dir: 2048, var: 1024}
}

let _want = #Desired & {in: _testHost}

#Expect: close({
	mkdirs: [...string]
	writes: [...string] // paths, in order
	daemonReload: bool
	restartK3s:   bool
	installK3s:   bool
	refuse:       bool
	// When given, the exact /etc/environment text written.
	env?: string
})

#Case: {
	have: {
		config:     *_want.config | string
		dropin:     *_want.dropin | string
		env:        *"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin\nK3S_DATA_DIR=/home/k3s\n" | string
		k3sVersion: *"k3s version v1.32.5+k3s1 (8e8f2a47)\ngo version go1.23.8\n" | string
		oldDataDir: *false | bool
	}
	want: #Expect

	let h = have
	let p = #Plan & {host: _testHost, have: h}
	got: #Expect & {
		mkdirs: p.mkdirs
		writes: [for w in p.writes {w.path}]
		daemonReload: p.daemonReload
		restartK3s:   p.restartK3s
		installK3s:   p.installK3s
		refuse:       p.refuse
		if want.env != _|_ {
			env: [for w in p.writes if w.path == #Paths.env {w.contents}][0]
		}
	}
	got: want
}

// Nothing to do. Defaults, so a case overrides only what it expects to happen.
let _none = {
	mkdirs:       *[] | [...string]
	writes:       *[] | [...string]
	daemonReload: *false | bool
	restartK3s:   *false | bool
	installK3s:   *false | bool
	refuse:       *false | bool
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
		have: {config: "", dropin: "", env: "", k3sVersion: ""}
		// install.sh reloads systemd and starts k3s itself.
		want: _none & {
			mkdirs: [#Paths.configDir, #Paths.dropinDir]
			writes: [#Paths.config, #Paths.dropin, #Paths.env]
			installK3s: true
		}
	}
	versionDrift: {
		have: k3sVersion: "k3s version v1.31.9+k3s1 (abcdef12)\n"
		want: _none & {installK3s: true}
	}
	oldDataDirRefused: {
		// Even with every file wrong, nothing is planned but the refusal.
		have: {config: "", dropin: "", env: "", k3sVersion: "", oldDataDir: true}
		want: _none & {refuse: true}
	}
}
