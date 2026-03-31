#!/usr/bin/env bats

setup() {
	repo_root="${BATS_TEST_DIRNAME}/.."
	test_tmp="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
	build_dir="${test_tmp}/build"
	other_build_dir="${test_tmp}/other-build"
	cache_dir="${test_tmp}/cache"
	env_dir="${test_tmp}/env"
	layers_dir="${test_tmp}/layers"
	platform_dir="${test_tmp}/platform"
	plan_path="${test_tmp}/plan.toml"
	stub_bin_dir="${test_tmp}/bin"
	test_token_env_var="BUILDPACK_TEST_AWS_CODEARTIFACT_TOKEN"

	mkdir -p "${build_dir}" "${other_build_dir}" "${cache_dir}" "${env_dir}" "${layers_dir}" "${platform_dir}" "${stub_bin_dir}"
	rm -f "${repo_root}/export"
}

teardown() {
	rm -f "${repo_root}/export"
	rm -rf "${test_tmp}"
}

write_pyproject_with_uv_index() {
	local header="${1:-[[tool.uv.index]]}"

	cat >"${build_dir}/pyproject.toml" <<EOF
${header}
name = "codeartifact"
url = "https://example.invalid/simple/"
EOF
}

write_pyproject_without_uv_index() {
	cat >"${build_dir}/pyproject.toml" <<'EOF'
[project]
name = "example"
version = "0.1.0"
EOF
}

write_env_file() {
	local name="${1}"
	local value="${2}"

	printf '%s' "${value}" >"${env_dir}/${name}"
}

write_aws_stub() {
	cat >"${stub_bin_dir}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' 'stub-token-123'
EOF
	chmod +x "${stub_bin_dir}/aws"
}

run_compile() {
	PATH="${stub_bin_dir}:${PATH}" run "${repo_root}/bin/compile" "${build_dir}" "${cache_dir}" "${env_dir}"
}

run_build() {
	run env \
		PATH="${stub_bin_dir}:${PATH}" \
		CNB_APP_DIR="${build_dir}" \
		"${repo_root}/bin/build" "${layers_dir}" "${platform_dir}" "${plan_path}"
}

@test "detect succeeds when pyproject.toml contains a uv index block" {
	write_pyproject_with_uv_index

	run "${repo_root}/bin/detect" "${build_dir}"

	[ "${status}" -eq 0 ]
	[ "${output}" = "AWS CodeArtifact uv auth" ]
}

@test "detect succeeds when uv index header contains valid TOML whitespace" {
	write_pyproject_with_uv_index "[[ tool.uv.index ]]"

	run "${repo_root}/bin/detect" "${build_dir}"

	[ "${status}" -eq 0 ]
	[ "${output}" = "AWS CodeArtifact uv auth" ]
}

@test "detect succeeds when uv index header is indented" {
	write_pyproject_with_uv_index "  [[tool.uv.index]]"

	run "${repo_root}/bin/detect" "${build_dir}"

	[ "${status}" -eq 0 ]
	[ "${output}" = "AWS CodeArtifact uv auth" ]
}

@test "detect fails when pyproject.toml is missing" {
	run "${repo_root}/bin/detect" "${build_dir}"

	[ "${status}" -eq 1 ]
}

@test "detect fails when pyproject.toml has no uv index block" {
	write_pyproject_without_uv_index

	run "${repo_root}/bin/detect" "${build_dir}"

	[ "${status}" -eq 1 ]
}

@test "detect uses the explicit build dir even when the caller cwd has a uv index" {
	write_pyproject_without_uv_index

	cat >"${other_build_dir}/pyproject.toml" <<'EOF'
[[tool.uv.index]]
name = "codeartifact"
url = "https://example.invalid/simple/"
EOF

	pushd "${other_build_dir}" >/dev/null
	run "${repo_root}/bin/detect" "${build_dir}"
	popd >/dev/null

	[ "${status}" -eq 1 ]
}

@test "compile succeeds without AWS_CODEARTIFACT_REPOSITORY" {
	write_pyproject_with_uv_index
	write_aws_stub
	write_env_file "AWS_CODEARTIFACT_DOMAIN" "example"
	write_env_file "AWS_CODEARTIFACT_DOMAIN_OWNER" "123456789012"
	write_env_file "AWS_CODEARTIFACT_REGION" "us-east-1"

	run_compile

	[ "${status}" -eq 0 ]
	[ -f "${repo_root}/export" ]
}

@test "compile fails when aws CLI is unavailable" {
	write_pyproject_with_uv_index
	write_env_file "AWS_CODEARTIFACT_DOMAIN" "example"
	write_env_file "AWS_CODEARTIFACT_DOMAIN_OWNER" "123456789012"
	write_env_file "AWS_CODEARTIFACT_REGION" "us-east-1"

	PATH="/usr/bin:/bin" run "${repo_root}/bin/compile" "${build_dir}" "${cache_dir}" "${env_dir}"

	[ "${status}" -eq 1 ]
	[[ "${output}" == *"AWS CLI is required but was not found on PATH"* ]]
}

@test "compile writes uv exports using the default index name" {
	write_pyproject_with_uv_index
	write_aws_stub
	write_env_file "AWS_CODEARTIFACT_DOMAIN" "example"
	write_env_file "AWS_CODEARTIFACT_DOMAIN_OWNER" "123456789012"
	write_env_file "AWS_CODEARTIFACT_REGION" "us-east-1"

	run_compile

	[ "${status}" -eq 0 ]
	[ -f "${repo_root}/export" ]
	run grep -F "export UV_INDEX_CODEARTIFACT_USERNAME=aws" "${repo_root}/export"
	[ "${status}" -eq 0 ]
	run grep -F "export UV_INDEX_CODEARTIFACT_PASSWORD=stub-token-123" "${repo_root}/export"
	[ "${status}" -eq 0 ]
}

@test "compile accepts uv index headers with valid TOML whitespace" {
	write_pyproject_with_uv_index "[[ tool.uv.index ]]"
	write_aws_stub
	write_env_file "AWS_CODEARTIFACT_DOMAIN" "example"
	write_env_file "AWS_CODEARTIFACT_DOMAIN_OWNER" "123456789012"
	write_env_file "AWS_CODEARTIFACT_REGION" "us-east-1"

	run_compile

	[ "${status}" -eq 0 ]
	[ -f "${repo_root}/export" ]
}

@test "compile normalizes custom index names" {
	write_pyproject_with_uv_index
	write_aws_stub
	write_env_file "AWS_CODEARTIFACT_DOMAIN" "example"
	write_env_file "AWS_CODEARTIFACT_DOMAIN_OWNER" "123456789012"
	write_env_file "AWS_CODEARTIFACT_REGION" "us-east-1"
	write_env_file "UV_CODEARTIFACT_INDEX_NAME" "private-prod"

	run_compile

	[ "${status}" -eq 0 ]
	run grep -F "export UV_INDEX_PRIVATE_PROD_USERNAME=aws" "${repo_root}/export"
	[ "${status}" -eq 0 ]
	run grep -F "export UV_INDEX_PRIVATE_PROD_PASSWORD=stub-token-123" "${repo_root}/export"
	[ "${status}" -eq 0 ]
}

@test "compile logs AWS config context before fetching token" {
	write_pyproject_with_uv_index
	write_aws_stub
	write_env_file "AWS_CODEARTIFACT_DOMAIN" "my-domain"
	write_env_file "AWS_CODEARTIFACT_DOMAIN_OWNER" "123456789012"
	write_env_file "AWS_CODEARTIFACT_REGION" "ap-southeast-1"

	run_compile

	[ "${status}" -eq 0 ]
	[[ "${output}" == *"domain:       my-domain"* ]]
	[[ "${output}" == *"domain-owner: 123456789012"* ]]
	[[ "${output}" == *"region:       ap-southeast-1"* ]]
}

@test "compile logs masked AWS_ACCESS_KEY_ID when set" {
	write_pyproject_with_uv_index
	write_aws_stub
	write_env_file "AWS_CODEARTIFACT_DOMAIN" "example"
	write_env_file "AWS_CODEARTIFACT_DOMAIN_OWNER" "123456789012"
	write_env_file "AWS_CODEARTIFACT_REGION" "us-east-1"
	write_env_file "AWS_ACCESS_KEY_ID" "AKIAIOSFODNN7EXAMPLE"

	run_compile

	[ "${status}" -eq 0 ]
	[[ "${output}" == *"AWS_ACCESS_KEY_ID is set (key ID: AKIAIOSF...)"* ]]
}

@test "compile logs session token presence when AWS_SESSION_TOKEN is set" {
	write_pyproject_with_uv_index
	write_aws_stub
	write_env_file "AWS_CODEARTIFACT_DOMAIN" "example"
	write_env_file "AWS_CODEARTIFACT_DOMAIN_OWNER" "123456789012"
	write_env_file "AWS_CODEARTIFACT_REGION" "us-east-1"
	write_env_file "AWS_ACCESS_KEY_ID" "ASIAIOSFODNN7EXAMPLE"
	write_env_file "AWS_SESSION_TOKEN" "FakeSessionToken"

	run_compile

	[ "${status}" -eq 0 ]
	[[ "${output}" == *"AWS_SESSION_TOKEN is set (temporary credentials)"* ]]
}

@test "compile surfaces AWS CLI error message when token fetch fails" {
	write_pyproject_with_uv_index
	cat >"${stub_bin_dir}/aws" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "aws-cli/2.0.0 stub" ;;
  *) echo "An error occurred (UnrecognizedClientException) when calling the GetAuthorizationToken operation: The security token included in the request is invalid." >&2; exit 1 ;;
esac
EOF
	chmod +x "${stub_bin_dir}/aws"
	write_env_file "AWS_CODEARTIFACT_DOMAIN" "example"
	write_env_file "AWS_CODEARTIFACT_DOMAIN_OWNER" "123456789012"
	write_env_file "AWS_CODEARTIFACT_REGION" "us-east-1"

	run_compile

	[ "${status}" -eq 1 ]
	[[ "${output}" == *"AWS CLI call failed"* ]]
	[[ "${output}" == *"UnrecognizedClientException"* ]]
}

@test "cnb detect succeeds when run from an app directory" {
	write_pyproject_with_uv_index

	pushd "${build_dir}" >/dev/null
	run "${repo_root}/bin/detect" "${platform_dir}"
	popd >/dev/null

	[ "${status}" -eq 0 ]
	[[ "${output}" == *'[[provides]]'* ]]
}

@test "cnb detect fails with exit 100 when no uv index is present" {
	write_pyproject_without_uv_index

	pushd "${build_dir}" >/dev/null
	run "${repo_root}/bin/detect" "${platform_dir}"
	popd >/dev/null

	[ "${status}" -eq 100 ]
}

@test "build fails when aws CLI is unavailable and no test token is provided" {
	write_pyproject_with_uv_index
	run env PATH="/usr/bin:/bin" CNB_APP_DIR="${build_dir}" "${repo_root}/bin/build" "${layers_dir}" "${platform_dir}" "${plan_path}"

	[ "${status}" -eq 1 ]
	[[ "${output}" == *"AWS CLI is required but was not found on PATH"* ]]
}

@test "build succeeds with a test token override and writes downstream env files" {
	write_pyproject_with_uv_index

	run env \
		CNB_APP_DIR="${build_dir}" \
		"${test_token_env_var}=test-token-456" \
		"${repo_root}/bin/build" "${layers_dir}" "${platform_dir}" "${plan_path}"

	[ "${status}" -eq 0 ]
	run cat "${layers_dir}/codeartifact-env/env.build/UV_INDEX_CODEARTIFACT_USERNAME.override"
	[ "${status}" -eq 0 ]
	[ "${output}" = "aws" ]
	run cat "${layers_dir}/codeartifact-env/env.build/UV_INDEX_CODEARTIFACT_PASSWORD.override"
	[ "${status}" -eq 0 ]
	[ "${output}" = "test-token-456" ]
}

@test "build normalizes custom index names for downstream env files" {
	write_pyproject_with_uv_index

	run env \
		CNB_APP_DIR="${build_dir}" \
		UV_CODEARTIFACT_INDEX_NAME="private-prod" \
		"${test_token_env_var}=test-token-456" \
		"${repo_root}/bin/build" "${layers_dir}" "${platform_dir}" "${plan_path}"

	[ "${status}" -eq 0 ]
	run cat "${layers_dir}/codeartifact-env/env.build/UV_INDEX_PRIVATE_PROD_USERNAME.override"
	[ "${status}" -eq 0 ]
	[ "${output}" = "aws" ]
	run cat "${layers_dir}/codeartifact-env/env.build/UV_INDEX_PRIVATE_PROD_PASSWORD.override"
	[ "${status}" -eq 0 ]
	[ "${output}" = "test-token-456" ]
}

@test "build fails when the test token override is empty" {
	write_pyproject_with_uv_index

	run env \
		CNB_APP_DIR="${build_dir}" \
		"${test_token_env_var}=" \
		"${repo_root}/bin/build" "${layers_dir}" "${platform_dir}" "${plan_path}"

	[ "${status}" -eq 1 ]
	[[ "${output}" == *"Failed to fetch a valid AWS CodeArtifact authorization token"* ]]
}
