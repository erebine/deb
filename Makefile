# Xerotier Debian packaging Makefile

TAG ?=

.PHONY: build
build: ## Download the latest stable binaries and build .deb packages
	TAG="$(TAG)" ./build.sh

.PHONY: clean
clean: ## Remove build artifacts
	rm -rf build

.DEFAULT_GOAL := build
