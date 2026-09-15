# Derived courier databases

Build output, not source. `build-courier-dat.sh` produces these from
`context.json` and the userdb source; `deploy-services.sh` collects them here
from the cluster and hands them to kustomize.

Nothing in this directory is committed. `userdbshadow.dat` is password hashes
and must never be.

There is deliberately no `kustomization.yaml` here. An earlier version had one,
which was misleading: a kustomization covering only the generators cannot do the
job. `configMapGenerator` hashes content into the object name, and only
resources kustomize manages get their references rewritten to that name -- so
the Deployments have to be in the same kustomization or they end up pointing at
a name that does not exist. `deploy-services.sh` therefore assembles one in a
temporary directory containing both the generators and the rendered workloads.
