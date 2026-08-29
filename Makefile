# AI Setup — Makefile shim
#
# This repo's primary command runner is `Justfile`. This Makefile exists only
# as a fallback for environments where `just` isn't installed (e.g. some CI
# images). It delegates every target to `just`.
#
# Install just locally: `brew install just`

.DEFAULT_GOAL := help

.PHONY: help
help:
	@just --list 2>/dev/null || ( \
		echo "This repo uses 'just' as its command runner."; \
		echo "Install with: brew install just"; \
		echo "Then run: just --list"; \
		exit 1 )

# Delegate every other target to just.
%:
	@just $@
