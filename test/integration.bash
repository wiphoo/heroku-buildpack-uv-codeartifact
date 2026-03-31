#!/usr/bin/env bash

set -euo pipefail

scenario="${1:-generic}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="${repo_root}/test/fixtures/minimal-app"
verifier_buildpack_dir="${repo_root}/test/support/buildpacks/verifier"

require_tool() {
	local tool="${1:?tool is required}"

	if ! command -v "${tool}" >/dev/null 2>&1; then
		echo "Required tool not found: ${tool}" >&2
		exit 1
	fi
	return 0
}

case "${scenario}" in
generic)
	builder="${TEST_BUILDER:-paketobuildpacks/builder-jammy-base}"
	image_name="${TEST_IMAGE_NAME:-aws-codeartifact-uv-generic-test}"
	;;
heroku | heroku-*)
	heroku_stack="${HEROKU_STACK:-${scenario#heroku-}}"
	if [[ -z "${heroku_stack}" || "${heroku_stack}" == "${scenario}" ]]; then
		heroku_stack="24"
	fi
	heroku_stack="${heroku_stack#heroku-}"
	builder="${TEST_BUILDER:-heroku/builder:${heroku_stack}}"
	image_name="${TEST_IMAGE_NAME:-aws-codeartifact-uv-heroku${heroku_stack}-test}"
	;;
*)
	echo "Unsupported integration scenario: ${scenario}" >&2
	exit 1
	;;
esac

cleanup() {
	docker image rm -f "${image_name}" >/dev/null 2>&1 || true
	return 0
}

trap cleanup EXIT

require_tool pack
require_tool docker

pack build "${image_name}" \
	--path "${fixture_dir}" \
	--builder "${builder}" \
	--pull-policy if-not-present \
	--buildpack "${repo_root}" \
	--buildpack "${verifier_buildpack_dir}" \
	--env "AWS_CODEARTIFACT_DOMAIN=example" \
	--env "AWS_CODEARTIFACT_DOMAIN_OWNER=123456789012" \
	--env "AWS_CODEARTIFACT_REGION=us-east-1" \
	--env "BUILDPACK_TEST_AWS_CODEARTIFACT_TOKEN=${BUILDPACK_TEST_AWS_CODEARTIFACT_TOKEN:-integration-token-123}"

output="$(docker run --rm "${image_name}")"

if [[ "${output}" != "integration-ok" ]]; then
	echo "Unexpected container output: ${output}" >&2
	exit 1
fi

printf '%s\n' "Integration scenario ${scenario} passed"
