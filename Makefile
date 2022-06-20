build-all: containers unit-files

install: build-all install-units

containers: service-images

install-units: unit-files
	cd unit-files && $(MAKE) install && \
	sudo systemctl daemon-reload 

unit-files/Makefile: unit-files/Makefile.template unit-files/files.json
	./render-template --context unit-files/files.json --template unit-files/Makefile.template > unit-files/Makefile

unit-files: render-template unit-files/Makefile
	cd unit-files && $(MAKE)

render-template:
	cd templater && cargo build; cd ..;  cp templater/target/debug/render-template .

service-images: courier-packages.tar build-services.sh
	sudo ./build-services.sh

courier-packages.tar: build-base.sh
	sudo ./build-base.sh

goss-bin:
	curl -L https://github.com/aelsabbahy/goss/releases/download/v0.3.18/goss-linux-amd64 > goss-bin && \
	  chmod +x goss-bin

run-goss: goss-bin
	(cd goss && ../goss-bin --vars ../context.json validate)
