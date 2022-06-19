

courier-mta.service: render-template
	./render-template --context context.json --template courier.mta.service.template > courier.mta.service

courier-mta.service: render-template
	./render-template --context context.json --template unit-files/courier.mta.service.template > unit-files/courier.mta.service

render-template:
	cd templater && cargo build; cd ..;  cp templater/target/debug/render-template .

service-images: courier-packages.tar
	./build-services.sh

courier-packages.tar:
	./build-base.sh
