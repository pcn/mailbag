GOSS_VER = "0.4.8"


dummy:
	@echo "targets: service-images, install or host"

install: build-artifacts  install-units


install-units: unit-files
	cd unit-files && $(MAKE) RENDERER=$(RENDERER) install && \
	sudo systemctl daemon-reload

courier-packages.tar: build-base.sh
	sudo ./build-base.sh

run-goss: goss-bin
	(cd goss && ../goss-bin --vars ../context.json validate)

start: unit-files
	cd unit-files && $(MAKE) RENDERER=$(RENDERER) start-services

stop: unit-files
	cd unit-files && $(MAKE) RENDERER=$(RENDERER) stop-services

## Pre-requisites
# The template renderer is upstream minijinja-cli, pinned by version and sha256
# in the context's .tools.minijinja_cli and fetched into a cache on first use.
# Deferred (=) so targets that do not render never fetch it.
RENDERER = $(shell scripts/fetch-renderer.sh examples/example-context.json)

# Render every template against its context; fails on any reference to a
# context key that is not provided.
check-templates:
	./scripts/render-all-templates.sh

# Assert every config we replace still covers its shipped .dist. Reads the
# .dist files from the image, so a courier version bump that adds a setting
# fails here rather than at runtime.
check-config:
	./scripts/check-config-completeness.sh

checks: check-templates check-config

goss-bin:
	curl -L https://github.com/aelsabbahy/goss/releases/download/v$(GOSS_VER)/goss-linux-amd64 > goss-bin && \
	  chmod +x goss-bin

## Build targets are now built by github actions, and downloaded in Dockerfile-base
build-artifacts: containers
# build-artifacts: containers unit-files
containers: service-images

## Runtime targets

host: host/Makefile
	cd host; $(MAKE)

host/Makefile: host/Makefile.template context.json
	$(RENDERER) --strict -n host/Makefile.template context.json > host/Makefile

unit-files/Makefile: unit-files/Makefile.template unit-files/files.json
	$(RENDERER) --strict -n unit-files/Makefile.template unit-files/files.json > unit-files/Makefile

# The generated unit-files/Makefile renders each unit with $(RENDERER) too.
unit-files: unit-files/Makefile
	cd unit-files && $(MAKE) RENDERER=$(RENDERER)
