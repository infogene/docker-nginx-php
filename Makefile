#!make

TARGET_ARGV = $(shell echo $(filter-out $@,$(MAKECMDGOALS)))

default: help
.PHONY: default

## Run docker build
build:
	@test -z $(TARGET_ARGV) || docker build -t ghcr.io/infogene/nginx-php:$(TARGET_ARGV) .
	@test ! -z $(TARGET_ARGV) || docker build -t ghcr.io/infogene/nginx-php:latest .
.PHONY: build-tag

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
