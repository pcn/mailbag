build-all: containers unit-files

install: build-all
	cp unit-files/*.service /etc/systemd/system
	systemctl daemon-reload

containers: service-images

unit-files: postgresql.service docker-custom-net.service courier-mta.service

postgresql.service: render-template
	./render-template --context context.json --template unit-files/postgresql.service.template > unit-files/postgresql.service

docker-custom-net.service: render-template
	./render-template --context context.json --template unit-files/docker-custom-net.service.template > unit-files/docker-custom-net.service

courier-mta.service: render-template
	./render-template --context context.json --template unit-files/courier-mta.service.template > unit-files/courier-mta.service

render-template:
	cd templater && cargo build; cd ..;  cp templater/target/debug/render-template .

service-images: courier-packages.tar
	./build-services.sh

courier-packages.tar:
	./build-base.sh
