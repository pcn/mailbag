build-all: containers unit-files

install: build-all
	sudo cp unit-files/*.service /etc/systemd/system && \
	sudo cp unit-files/*.sh /usr/local/bin && \
	sudo chmod +x /usr/local/bin/*.sh && \
	sudo systemctl daemon-reload

containers: service-images

install: unit-files
	cp unit-files/*.sh /usr/local/bin && chmod 
	cp unit-files/*.service /etc/systemd/system && \
	  sudo systemctl daemon-reload


unit-files/Makefile:
	./render-template --context unit-files/files.json --template unit-files/Makefile.template > unit-files/Makefile

unit-files: render-template  unit-files/Makefile
	cd unit-files && $(MAKE)

render-template:
	cd templater && cargo build; cd ..;  cp templater/target/debug/render-template .

service-images: courier-packages.tar
	sudo ./build-services.sh

courier-packages.tar:
	sudo ./build-base.sh
