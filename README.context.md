# The context.json file

The `context.json` file contains the authoritative data that will be substituted in various places when templating
(using `jq` in the unit files startup, and the template renderer -- upstream minijinja-cli, whose version and checksums
are themselves pinned in the context under `tools.minijinja_cli` -- when expanding templates for a host or a container).

The example file contains the data, and the shape of the data, and any of the keys or values may be references in any
of the files in this repo, but that data is host-specific.
