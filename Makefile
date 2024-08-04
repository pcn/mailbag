GOSS_VER = "0.4.8"


dummy:
	@echo "targets: service-images, install or host"

install: build-artifacts  install-units


install-units: unit-files
	cd unit-files && $(MAKE) install && \
	sudo systemctl daemon-reload

courier-packages.tar: build-base.sh
	sudo ./build-base.sh

run-goss: goss-bin
	(cd goss && ../goss-bin --vars ../context.json validate)

start: unit-files
	cd unit-files && $(MAKE) start-services

stop: unit-files
	cd unit-files && $(MAKE) stop-services

## Pre-requisites
render-template:
	cd templater && cargo build; cd ..;  cp templater/target/debug/render-template .

goss-bin:
	curl -L https://github.com/aelsabbahy/goss/releases/download/v$(GOSS_VER)/goss-linux-amd64 > goss-bin && \
	  chmod +x goss-bin

## Build targets are now built by github actions, and downloaded in Dockerfile-base
build-artifacts: containers
# build-artifacts: containers unit-files
containers: service-images

# XXX I should be able to create the acceptmailfor and and hosteddomanins in the entryptpoints
#  why is this here?
# Yeah, this rendering should be done in the container
# service-images: build-services.sh render-template
# 	# mkdir -p target && \
# 	#  ./render-template --context context.json --template acceptmailfor.template > target/acceptmailfor && \
# 	#  ./render-template --context context.json --template hosteddomains.template > target/hosteddomains
# 	sudo ./build-services.sh

## Runtime targets

host: host/Makefile
	cd host; $(MAKE)

host/Makefile: host/Makefile.template context.json render-template
	./render-template --context context.json --template host/Makefile.template > host/Makefile

unit-files/Makefile: unit-files/Makefile.template unit-files/files.json render-template
	./render-template --context unit-files/files.json --template unit-files/Makefile.template > unit-files/Makefile

unit-files: render-template unit-files/Makefile
	cd unit-files && $(MAKE)
