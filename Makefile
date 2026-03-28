SHELL := bash
.DEFAULT_GOAL := help

.PHONY: help lint lint-shellcheck lint-format test check ci

help: ## Show available development commands
	@awk 'BEGIN {FS = ": ## "}; /^[a-zA-Z0-9_.-]+: ## / {printf "%-16s %s\n", $$1, $$2}' Makefile

lint: ## Run all lint checks
lint: lint-shellcheck lint-format

lint-shellcheck: ## Run shellcheck on scripts and tests
	shellcheck bin/* test/*.bash
	shellcheck -s bash test/buildpack.bats

lint-format: ## Verify shell formatting with shfmt
	shfmt -d bin test

test: ## Run the Bats test suite
	bats test/buildpack.bats

check: ## Run the standard local verification flow
check: lint test

ci: ## Run the same verification flow used in CI
ci: check
