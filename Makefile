build-all: containers unit-files

install: build-all install-units

containers: service-images

install-units: unit-files
	cd unit-files && $(MAKE) install && \
	sudo systemctl daemon-reload 

unit-files/Makefile: unit-files/Makefile.template
	./render-template --context unit-files/files.json --template unit-files/Makefile.template > unit-files/Makefile

unit-files: render-template unit-files/Makefile
	cd unit-files && $(MAKE)

render-template:
	cd templater && cargo build; cd ..;  cp templater/target/debug/render-template .

service-images: courier-packages.tar build-services.sh
	sudo ./build-services.sh

courier-packages.tar: build-base.sh
	sudo ./build-base.sh
