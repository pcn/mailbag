# The context.json file

`/etc/mailbag/context.json` is the one description of a host: hostnames,
ports, paths, the certificate source, the k3s settings, and the pinned tool
versions. The deploy scripts and the renderer read it, each container renders
its courier config from it, and the goss suites take their values from it.

`cue/schema.cue` defines what it may contain (`#Context`). It is closed, so a
key nothing reads is rejected rather than silently ignored.
`examples/example-context.json` is a complete example; `generate-context.sh`
writes a first one for a new host.
