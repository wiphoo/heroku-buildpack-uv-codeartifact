SHELL := bash
.DEFAULT_GOAL := help

.PHONY: help tools tools-lint tools-test tools-coverage lint test test-integration test-integration-generic test-integration-heroku coverage check ci

help: ## Show available development commands
	@awk 'BEGIN {FS = ": ## "}; /^[a-zA-Z0-9_.-]+: ## / {printf "%-16s %s\n", $$1, $$2}' Makefile

tools: ## Check all required tools
	@$(MAKE) --no-print-directory tools-lint
	@$(MAKE) --no-print-directory tools-test
	@echo "All required tools are installed"

tools-lint: ## Check lint tools
	@echo "Checking lint tools..."; \
	missing=0; \
	for tool in shellcheck shfmt; do \
		if ! command -v $$tool >/dev/null 2>&1; then \
			echo "Missing required tool: $$tool"; \
			missing=1; \
		fi; \
	done; \
	if [ $$missing -ne 0 ]; then \
		echo "Install on Ubuntu/Debian: sudo apt-get install -y shellcheck && go install mvdan.cc/sh/v3/cmd/shfmt@latest"; \
		exit 1; \
	fi; \
	echo "All lint tools are installed: shellcheck shfmt"

tools-test: ## Check test tools
	@echo "Checking test tools..."; \
	missing=0; \
	for tool in bats; do \
		if ! command -v $$tool >/dev/null 2>&1; then \
			echo "Missing required tool: $$tool"; \
			missing=1; \
		fi; \
	done; \
	if [ $$missing -ne 0 ]; then \
		echo "Install on Ubuntu/Debian: sudo apt-get update && sudo apt-get install -y bats"; \
		exit 1; \
	fi; \
	echo "All test tools are installed: bats"

lint: ## Run all lint checks
lint: tools-lint
	@echo "Running lint checks..."
	shellcheck bin/* lib/*.sh test/*.bash test/support/buildpacks/verifier/bin/*
	shellcheck -s bash test/buildpack.bats
	shfmt -d bin lib test
	@echo "Lint checks passed"

test: ## Run the Bats test suite
test: tools-test
	@echo "Running test suite..."
	bats test/buildpack.bats
	@echo "Test suite passed"

tools-coverage: ## Check coverage tooling
	@echo "Checking coverage tooling..."; \
	missing=0; \
	for tool in kcov python3; do \
		if ! command -v $$tool >/dev/null 2>&1; then \
			echo "Missing required tool: $$tool"; \
			missing=1; \
		fi; \
	done; \
	if [ $$missing -ne 0 ]; then \
		echo "Install coverage tooling: python3 via apt; kcov must be built from source — see https://github.com/SimonKagstrom/kcov"; \
		exit 1; \
	fi; \
	echo "Coverage tooling installed: kcov python3"

coverage: tools-test tools-coverage ## Generate a Sonar generic coverage report from kcov
	@echo "Generating coverage report..."
	@rm -rf coverage
	@mkdir -p coverage/kcov
	@kcov --clean --cobertura-only --include-path="$(CURDIR)/bin,$(CURDIR)/lib" coverage/kcov bats test/buildpack.bats
	@test -f coverage/kcov/cov.xml || { echo "kcov cobertura output not found at coverage/kcov/cov.xml; got:"; ls coverage/kcov/; exit 1; }
	@python3 test/support/kcov_to_sonar_generic.py coverage/kcov/cov.xml coverage/coverage.xml
	@test -f coverage/coverage.xml

test-integration: ## Run generic and Heroku-24 pack/docker integration tests
	@$(MAKE) --no-print-directory test-integration-generic
	@$(MAKE) --no-print-directory test-integration-heroku

test-integration-generic: ## Run the generic builder integration test
	test/integration.bash generic

test-integration-heroku: ## Run the Heroku-24 builder integration test
	test/integration.bash heroku-24

check: ## Run lint and tests
check: lint test
	@echo "All checks passed"

ci: ## Run CI checks
ci: check test-integration
	@echo "CI checks passed"
