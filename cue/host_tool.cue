package mailbag

import (
	"encoding/json"
	"tool/cli"
	"tool/exec"
	"tool/file"
)

// Host setup for a mailbag k3s node (PROJ-026). Run as root from the deploy
// tree (or a checkout), with the pinned cue (scripts/fetch-cue.sh):
//
//   cue cmd -t ctx="$(cat /etc/mailbag/context.json)" plan   ./cue   # print what apply would do
//   cue cmd -t ctx="$(cat /etc/mailbag/context.json)" apply  ./cue   # converge
//   cue cmd verify ./cue                                             # goss/host-k3s.yaml
//
// A context the schema rejects stops plan and apply before anything is read
// or changed: a wrong value (or a missing -t ctx) before any task runs, and a
// missing required field at the gate task, which needs the whole context
// complete. Either error names where the bad value was used, not the rule it
// broke. For a readable error:
//
//   cue vet -c -d '#Context' ./cue /etc/mailbag/context.json
//
// Orchestration only. Every decision is #Plan's (plan.cue), so it is tested
// without side effects (plan_tests.cue); goss/repo.yaml checks this file
// holds no comparisons and no strings or list calls. Rules from the spike
// (EVD-046), each required:
//  1. The context comes in as a tag holding its contents, not as a data file
//     (definitions stop resolving) and not read by a task (too late).
//  2. Guards on a task's output sit inside a struct under the command, never
//     at its top level.
//  3. Each file is read by one task that always succeeds; branch only on
//     #Plan's output, never on a glob.
//  4. Pass values into definitions under different names, or bind with let.
//
// Tags: ctx (required by plan and apply), ctxpath (default
// /etc/mailbag/context.json, for verify), root (a scratch prefix for every
// managed path, for testing; default none).

_ctxJSON: string @tag(ctx)
_ctxPath: *"/etc/mailbag/context.json" | string @tag(ctxpath)
_root:    *"" | string @tag(root)

_ctx: #Context & json.Unmarshal(_ctxJSON)
_at:  (#Rooted & {root: _root}).paths

// Everything #Plan needs to know about the host.
_read: {
	// The gate: a context missing a required field is only incomplete, which
	// #Plan would not notice unless it needed that field. Marshalling the
	// whole context fails here ("invalid environment variable value") before
	// anything is read, and everything else runs after the reads.
	gate: exec.Run & {cmd: ["true"], env: MAILBAG_CONTEXT: json.Marshal(_ctx)}

	config: exec.Run & {cmd: ["cat", _at.config], stdout: string, stderr: string, mustSucceed: false, $after: gate}
	dropin: exec.Run & {cmd: ["cat", _at.dropin], stdout: string, stderr: string, mustSucceed: false, $after: gate}
	env:    exec.Run & {cmd: ["cat", _at.env], stdout: string, stderr: string, mustSucceed: false, $after: gate}
	k3s:    exec.Run & {cmd: ["sh", "-c", "k3s --version 2>/dev/null || true"], stdout: string, $after: gate}
	old:    exec.Run & {cmd: ["test", "-e", _at.oldDataDir], mustSucceed: false, $after: gate}
}

command: plan: {
	read: _read
	decide: {
		let p = #Plan & {
			host: _ctx.host
			root: _root
			have: {
				config:     read.config.stdout
				dropin:     read.dropin.stdout
				env:        read.env.stdout
				k3sVersion: read.k3s.stdout
				oldDataDir: read.old.success
			}
		}
		print: cli.Print & {text: p.summary}
		if p.refuse {
			stop: exec.Run & {cmd: ["false"], $after: print}
		}
	}
}

command: apply: {
	read: _read
	converge: {
		let p = #Plan & {
			host: _ctx.host
			root: _root
			have: {
				config:     read.config.stdout
				dropin:     read.dropin.stdout
				env:        read.env.stdout
				k3sVersion: read.k3s.stdout
				oldDataDir: read.old.success
			}
		}
		print: cli.Print & {text: p.summary}
		if p.refuse {
			stop: exec.Run & {cmd: ["false"], $after: print}
		}
		mkdir: {for i, d in p.mkdirs {
			"\(i)": file.MkdirAll & {path: d, permissions: 0o755, $after: print}
		}}
		write: {for i, w in p.writes {
			"\(i)": file.Create & {
				filename:    w.path
				contents:    w.contents
				permissions: 0o644
				$after: [for _, t in mkdir {t}]
			}
		}}
		if p.runScript {
			run: exec.Run & {
				cmd: ["sh", "-c", p.script]
				$after: [print, for _, t in write {t}]
			}
		}
	}
}

command: verify: {
	goss: exec.Run & {
		cmd: ["sh", "-c", """
			GOSS=$(scripts/fetch-goss.sh "$1") &&
			exec "$GOSS" -g goss/host-k3s.yaml --vars "$1" validate --format documentation
			""", "verify", _ctxPath]
	}
}
