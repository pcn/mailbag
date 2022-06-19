build-all: containers unit-files

install: build-all
	sudo cp unit-files/*.service /etc/systemd/system && \
	sudo cp unit-files/*.sh /usr/local/bin && \
	sudo chmod +x /usr/local/bin/*.sh && \
	sudo systemctl daemon-reload

containers: service-images

unit-files: postgresql.service vmail-custom-net.service courier-mta.service

postgresql.service: render-template
	./render-template --context context.json --template unit-files/postgresql.service.template > unit-files/postgresql.service

vmail-custom-net.service: render-template
	./render-template --context context.json --template unit-files/vmail-custom-net.service.template > unit-files/vmail-custom-net.service
	./render-template --context context.json --template unit-files/vmail-custom-net.sh.template > unit-files/vmail-custom-net.sh

courier-mta.service: render-template
	./render-template --context context.json --template unit-files/courier-mta.service.template > unit-files/courier-mta.service

render-template:
	cd templater && cargo build; cd ..;  cp templater/target/debug/render-template .

service-images: courier-packages.tar
	sudo ./build-services.sh

courier-packages.tar:
	sudo ./build-base.sh
