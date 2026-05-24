.PHONY: build bundle run run-debug clean

build:
	swift build

bundle:
	./scripts/build-app.sh

run: bundle
	open .build/Mia.app

run-debug: build
	.build/debug/Mia

clean:
	rm -rf .build
	swift package clean
