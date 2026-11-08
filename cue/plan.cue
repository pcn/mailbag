package mailbag

import (
	"list"
	"strings"
)

// #Plan decides everything host setup does (PROJ-026). Given the host block
// and what is on the host now, it returns the directories to create, the
// files to write, the commands to run and a summary. Pure, so every decision
// is tested by plan_tests.cue; host_tool.cue only reads the inputs and runs
// the result.
#Plan: {
	host: #Host
	// Prefix for every managed path: "" on a real host, a scratch directory
	// when testing the tool layer.
	root: *"" | =~"^/.*[^/]$"
	have: {
		config: string // current text of each managed file, "" when missing
		dropin: string
		env:    string
		// Output of `k3s --version`, "" when k3s is not installed.
		k3sVersion: string
		// Whether k3s data still exists under /var/lib/rancher/k3s.
		oldDataDir: bool
	}

	let want = #Desired & {in: host}
	let r = root
	let at = (#Rooted & {root: r}).paths
	let envText = (#EnvEdit & {text: have.env, key: "K3S_DATA_DIR", line: want.envLine}).out

	// "k3s version v1.32.5+k3s1 (8e8f2a47)" on the first line.
	let fields = strings.Fields(strings.Split(have.k3sVersion, "\n")[0])
	// Guards nest so fields is indexed only when long enough.
	installed: [
		if len(fields) >= 3 {[if fields[0] == "k3s" && fields[1] == "version" {fields[2]}, ""][0]},
		"",
	][0]

	// Refuse before changing anything while k3s data is still under /var:
	// moving it is a manual, verified procedure, not something to automate.
	refuse: have.oldDataDir
	let go = !refuse

	let configChanged = go && have.config != want.config
	let dropinChanged = go && have.dropin != want.dropin
	let envChanged = go && have.env != envText
	installK3s: go && installed != want.version
	// install.sh reloads systemd and (re)starts k3s itself.
	daemonReload: dropinChanged && !installK3s
	// Restarting k3s does not stop the mail pods (KillMode=process).
	restartK3s: (configChanged || dropinChanged) && !installK3s

	let why = {
		config: [if have.config == "" {"missing"}, "differs"][0]
		dropin: [if have.dropin == "" {"missing"}, "differs"][0]
		env:    [if have.env == "" {"missing"}, "K3S_DATA_DIR line"][0]
	}

	mkdirs: [
		if configChanged {at.configDir},
		if dropinChanged {at.dropinDir},
	]
	writes: [
		if configChanged {{path: at.config, contents: want.config, reason: why.config}},
		if dropinChanged {{path: at.dropin, contents: want.dropin, reason: why.dropin}},
		if envChanged {{path: at.env, contents: envText, reason: why.env}},
	]

	// Run after the writes, in one shell so the order is the plan's.
	let installScript = """
		f=$(mktemp)
		trap 'rm -f "$f"' EXIT
		curl -fsSL -o "$f" '\(want.installURL)'
		echo '\(want.installSha256)  '"$f" | sha256sum -c -
		INSTALL_K3S_VERSION='\(want.version)' sh "$f"
		"""
	script: strings.Join(list.Concat([
		["set -eu"],
		[if daemonReload {"systemctl daemon-reload"}],
		[if restartK3s {"systemctl restart k3s"}],
		[if installK3s {installScript}],
	]), "\n")
	runScript: daemonReload || restartK3s || installK3s

	let steps = list.Concat([
		[for w in writes {"  write \(w.path) (\(w.reason))"}],
		[if daemonReload {"  systemctl daemon-reload"}],
		[if restartK3s {"  restart k3s"}],
		[if installK3s {"  install k3s \(want.version) (installed: \([if installed == "" {"none"}, installed][0]))"}],
	])

	refusal: """
		k3s host setup: refusing, nothing changed. k3s data is still under
		\(at.oldDataDir), and host setup does not migrate it. Move it by
		hand first, as verified on farout (PROJ-028):
		  1. systemctl stop k3s && k3s-killall.sh
		  2. cp -a \(#Paths.oldDataDir) \(host.k3s.data_dir)
		  3. in the six \(host.k3s.data_dir)/server/cred/*.kubeconfig files, rewrite
		     \(#Paths.oldDataDir) to \(host.k3s.data_dir)
		  4. mv \(#Paths.oldDataDir) \(#Paths.oldDataDir).old
		  5. cue cmd apply (writes data-dir and K3S_DATA_DIR, starts k3s), check
		     the node, then remove \(#Paths.oldDataDir).old
		"""

	summary: [
		if refuse {refusal},
		if len(steps) == 0 {"k3s host setup: in sync"},
		"k3s host setup: \(len(steps)) change(s)\n" + strings.Join(steps, "\n"),
	][0]
}
