# Repository checks. Images are built by CI (.github/workflows), and deployment
# to k3s is deploy-mailbag.sh / deployment/k8s/deploy-services.sh.

.PHONY: checks check-templates check-config check-goss-repo

checks: check-templates check-config check-goss-repo

# goss is upstream goss, pinned by version and sha256 in the context's
# .tools.goss and fetched into a cache on first use. Deferred (=) so targets
# that do not need it never fetch it.
GOSS = $(shell scripts/fetch-goss.sh examples/example-context.json)

# Repo-level goss suite: no cluster, no credentials. Also run in CI.
check-goss-repo:
	$(GOSS) -g goss/repo.yaml validate

# Render every template against the example context; fails on any reference
# to a context key that is not provided.
check-templates:
	./scripts/render-all-templates.sh

# Assert every config we replace still covers its shipped .dist. Reads the
# .dist files from the image, so a courier version bump that adds a setting
# fails here rather than at runtime.
check-config:
	./scripts/check-config-completeness.sh
