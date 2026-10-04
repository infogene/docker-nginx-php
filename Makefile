#!make

TARGET_ARGV = $(shell echo $(filter-out $@,$(MAKECMDGOALS)))
VCS_REF = $(shell git rev-parse HEAD 2>/dev/null)

default: help
.PHONY: default

## Run docker build
build-tag:
	@test -z $(TARGET_ARGV) || docker build --build-arg "VCS_REF=$(VCS_REF)" --build-arg "PHP_VERSION=$(TARGET_ARGV)" --pull --no-cache -f Dockerfile.debian -t ghcr.io/infogene/nginx-php:$(TARGET_ARGV)-debian .
	@test -z $(TARGET_ARGV) || docker build --build-arg "VCS_REF=$(VCS_REF)" --build-arg "PHP_VERSION=$(TARGET_ARGV)" --pull --no-cache -f Dockerfile.alpine -t ghcr.io/infogene/nginx-php:$(TARGET_ARGV)-alpine .
	@test -z $(TARGET_ARGV) || docker tag ghcr.io/infogene/nginx-php:$(TARGET_ARGV)-alpine ghcr.io/infogene/nginx-php:$(TARGET_ARGV)
	@test ! -z $(TARGET_ARGV) || docker build --build-arg "VCS_REF=$(VCS_REF)" --pull --no-cache -f Dockerfile.debian -t ghcr.io/infogene/nginx-php:latest-debian .
	@test ! -z $(TARGET_ARGV) || docker build --build-arg "VCS_REF=$(VCS_REF)" --pull --no-cache -f Dockerfile.alpine -t ghcr.io/infogene/nginx-php:latest-alpine .
	@test ! -z $(TARGET_ARGV) || docker tag ghcr.io/infogene/nginx-php:latest-alpine ghcr.io/infogene/nginx-php:latest
.PHONY: build-tag

## Push docker image to ghcr.io/infogene/nginx-php
push-tag:
	@test -z $(TARGET_ARGV) || docker push ghcr.io/infogene/nginx-php:$(TARGET_ARGV)-debian
	@test -z $(TARGET_ARGV) || docker push ghcr.io/infogene/nginx-php:$(TARGET_ARGV)-alpine
	@test -z $(TARGET_ARGV) || docker push ghcr.io/infogene/nginx-php:$(TARGET_ARGV)
	@test ! -z $(TARGET_ARGV) || docker push ghcr.io/infogene/nginx-php:latest-debian
	@test ! -z $(TARGET_ARGV) || docker push ghcr.io/infogene/nginx-php:latest-alpine
	@test ! -z $(TARGET_ARGV) || docker push ghcr.io/infogene/nginx-php:latest
.PHONY: push-tag

## Smoke-test the images built by build-tag (tests/smoke-test, also run by CI)
smoke-test:
	@sh tests/smoke-test ghcr.io/infogene/nginx-php:$(or $(TARGET_ARGV),latest)-debian
	@sh tests/smoke-test ghcr.io/infogene/nginx-php:$(or $(TARGET_ARGV),latest)-alpine
.PHONY: smoke-test

%:
	@:

## This help screen
help:
	@printf "Available targets:\n\n"
	@awk '/^[a-zA-Z\-\_0-9%:\\]+/ { \
	  helpMessage = match(lastLine, /^## (.*)/); \
	  if (helpMessage) { \
		helpCommand = $$1; \
		helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
	gsub("\\\\", "", helpCommand); \
	gsub(":+$$", "", helpCommand); \
		printf "  \x1b[32;01m%-35s\x1b[0m %s\n", helpCommand, helpMessage; \
	  } \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)
	@printf "\n"
