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
	// The context's tls.source: cert-manager is installed only when it issues
	// the certificate (PROJ-027).
	tlsSource: "cert-manager" | "secret"
	// Prefix for every managed path: "" on a real host, a scratch directory
	// when testing the tool layer.
	root: *"" | =~"^/.*[^/]$"
	have: {
		config:    string // current text of each managed file, "" when missing
		dropin:    string
		env:       string
		journald:  string
		logrotate: string
		// Output of `k3s --version`, "" when k3s is not installed.
		k3sVersion: string
		// Whether k3s data still exists under /var/lib/rancher/k3s.
		oldDataDir: bool
		// The cert-manager controller deployment's image, "" when there is
		// none (or the API did not answer).
		certManagerImage: string
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

	// Log limits (PROJ-044). journald reads its drop-ins only at start;
	// logrotate reads its files at each run, so needs nothing.
	let journaldChanged = go && have.journald != want.journald
	let logrotateChanged = go && have.logrotate != want.logrotate
	restartJournald: journaldChanged

	// "quay.io/jetstack/cert-manager-controller:v1.21.2" -> "v1.21.2".
	let imageParts = strings.Split(have.certManagerImage, ":")
	certManagerInstalled: [
		if have.certManagerImage != "" && len(imageParts) > 1 {imageParts[len(imageParts)-1]},
		"",
	][0]
	// Only when the deployed version differs, so a re-run at the same
	// version applies nothing and the deployments' generations stay put.
	installCertManager: go && tlsSource == "cert-manager" && certManagerInstalled != want.certManager.version

	let why = {
		config: [if have.config == "" {"missing"}, "differs"][0]
		dropin: [if have.dropin == "" {"missing"}, "differs"][0]
		env: [if have.env == "" {"missing"}, "K3S_DATA_DIR line"][0]
		journald: [if have.journald == "" {"missing"}, "differs"][0]
		logrotate: [if have.logrotate == "" {"missing"}, "differs"][0]
	}

	mkdirs: [
		if configChanged {at.configDir},
		if dropinChanged {at.dropinDir},
		if journaldChanged {at.journaldDir},
		if logrotateChanged {at.logrotateDir},
	]
	writes: [
		if configChanged {{path: at.config, contents: want.config, reason: why.config}},
		if dropinChanged {{path: at.dropin, contents: want.dropin, reason: why.dropin}},
		if envChanged {{path: at.env, contents: envText, reason: why.env}},
		if journaldChanged {{path: at.journald, contents: want.journald, reason: why.journald}},
		if logrotateChanged {{path: at.logrotate, contents: want.logrotate, reason: why.logrotate}},
	]

	// Run after the writes, in one shell so the order is the plan's. Downloads
	// share one temp directory, removed on exit.
	let tempDir = """
		t=$(mktemp -d)
		trap 'rm -rf "$t"' EXIT
		"""
	let installScript = """
		curl -fsSL -o "$t/install.sh" '\(want.installURL)'
		echo '\(want.installSha256)  '"$t/install.sh" | sha256sum -c -
		INSTALL_K3S_VERSION='\(want.version)' sh "$t/install.sh"
		"""

	// Fetched and checked first, before k3s is touched or the cluster is
	// contacted: a wrong manifest changes nothing.
	let cm = want.certManager
	let fetchCertManager = """
		curl -fsSL -o "$t/cert-manager.yaml" '\(cm.manifestURL)'
		echo '\(cm.sha256)  '"$t/cert-manager.yaml" | sha256sum -c -
		"""

	// After any k3s restart or install, wait for the API before applying.
	let applyCertManager = """
		i=0
		until kubectl get --raw=/readyz >/dev/null 2>&1; do
		  i=$((i + 1))
		  [ "$i" -le 90 ] || { echo "k3s API not ready after 180s" >&2; exit 1; }
		  sleep 2
		done
		kubectl apply --server-side -f "$t/cert-manager.yaml"
		# rollout status, not wait --for=Available: during an upgrade the old
		# pods keep the deployments Available, so that would return at once.
		for d in cert-manager cert-manager-cainjector cert-manager-webhook; do
		  kubectl -n cert-manager rollout status "deploy/$d" --timeout=300s
		done
		"""
	script: strings.Join(list.Concat([
		["set -eu"],
		[if installK3s || installCertManager {tempDir}],
		[if installCertManager {fetchCertManager}],
		[if daemonReload {"systemctl daemon-reload"}],
		[if restartJournald {"systemctl restart systemd-journald"}],
		[if restartK3s {"systemctl restart k3s"}],
		[if installK3s {installScript}],
		[if installCertManager {applyCertManager}],
	]), "\n")
	runScript: daemonReload || restartJournald || restartK3s || installK3s || installCertManager

	let none = {in: string, out: [if in == "" {"none"}, in][0]}
	let steps = list.Concat([
		[for w in writes {"  write \(w.path) (\(w.reason))"}],
		[if daemonReload {"  systemctl daemon-reload"}],
		[if restartJournald {"  restart systemd-journald"}],
		[if restartK3s {"  restart k3s"}],
		[if installK3s {"  install k3s \(want.version) (installed: \((none & {in: installed}).out))"}],
		[if installCertManager {"  install cert-manager \(cm.version) (installed: \((none & {in: certManagerInstalled}).out))"}],
	])

	refusal: """
		host setup: refusing, nothing changed. k3s data is still under
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
		if len(steps) == 0 {"host setup: in sync"},
		"host setup: \(len(steps)) change(s)\n" + strings.Join(steps, "\n"),
	][0]
}
