

render-template:
	cd templater && cargo build && cp target/debug/render-template ../../..

service-images: courier-packages.tar
	./build-services.sh

courier-packages.tar:
	./build-base.sh
