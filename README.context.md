# The context.json file

The `context.json` file contains the authoritative data that will be substituted in various places when templating
(using `jq` in the unit files startup, the `render-template` component of this repo when expanding templates for a host, and
currently there are no other use cases).

The example file contains the data, and the shape of the data, and any of the keys or values may be references in any
of the files in this repo, but that data is host-specific.
