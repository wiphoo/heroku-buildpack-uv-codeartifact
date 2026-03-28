SHELL := bash

.PHONY: lint lint-shellcheck lint-format test ci

lint: lint-shellcheck lint-format

lint-shellcheck:
	shellcheck bin/* test/*.bash
	shellcheck -s bash test/buildpack.bats

lint-format:
	shfmt -d bin test

test:
	bats test/buildpack.bats

ci: lint test
