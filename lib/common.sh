#!/usr/bin/env bash

set -euo pipefail

readonly UV_INDEX_HEADER_PATTERN='^[[:space:]]*\[\[[[:space:]]*tool\.uv\.index[[:space:]]*\]\]'
readonly TEST_TOKEN_ENV_VAR="BUILDPACK_TEST_AWS_CODEARTIFACT_TOKEN"

log() {
	echo "-----> $*"
	return 0
}

log_error() {
	echo "-----> $*" >&2
	return 0
}

app_has_uv_index() {
	local app_dir="${1:?app directory is required}"

	[[ -f "${app_dir}/pyproject.toml" ]] || return 1
	grep -Eq "${UV_INDEX_HEADER_PATTERN}" "${app_dir}/pyproject.toml"
}

normalize_index_name() {
	local raw_name="${1:?index name is required}"

	printf '%s' "${raw_name}" |
		tr '[:lower:]' '[:upper:]' |
		sed -E 's/[^A-Z0-9]+/_/g; s/^_+//; s/_+$//'
	return 0
}

require_env() {
	local var_name="${1:?variable name is required}"

	if [[ -z "${!var_name:-}" ]]; then
		log_error "Missing required config var: ${var_name}"
		return 1
	fi
}

load_env_dir() {
	local env_dir="${1:?env directory is required}"

	[[ -d "${env_dir}" ]] || return 0

	while IFS= read -r -d '' env_file; do
		local varname value
		varname="$(basename "${env_file}")"
		value="$(<"${env_file}")"
		export "${varname}=${value}"
	done < <(find "${env_dir}" -maxdepth 1 -type f -print0)
}

fetch_codeartifact_token() {
	if [[ "${!TEST_TOKEN_ENV_VAR+x}" == "x" ]]; then
		printf '%s' "${!TEST_TOKEN_ENV_VAR}"
		return 0
	fi

	if ! command -v aws >/dev/null 2>&1; then
		log_error "AWS CLI is required but was not found on PATH"
		return 1
	fi

	require_env "AWS_CODEARTIFACT_DOMAIN" || return 1
	require_env "AWS_CODEARTIFACT_DOMAIN_OWNER" || return 1
	require_env "AWS_CODEARTIFACT_REGION" || return 1

	if [[ -n "${AWS_CODEARTIFACT_ACCESS_KEY_ID:-}" ]]; then
		export AWS_ACCESS_KEY_ID="${AWS_CODEARTIFACT_ACCESS_KEY_ID}"
	fi
	if [[ -n "${AWS_CODEARTIFACT_SECRET_ACCESS_KEY:-}" ]]; then
		export AWS_SECRET_ACCESS_KEY="${AWS_CODEARTIFACT_SECRET_ACCESS_KEY}"
	fi

	local aws_error token_output aws_error_file
	aws_error_file="$(mktemp)"
	if ! token_output="$(aws codeartifact get-authorization-token \
		--domain "${AWS_CODEARTIFACT_DOMAIN}" \
		--domain-owner "${AWS_CODEARTIFACT_DOMAIN_OWNER}" \
		--region "${AWS_CODEARTIFACT_REGION}" \
		--query authorizationToken \
		--output text 2>"${aws_error_file}")"; then
		aws_error="$(<"${aws_error_file}")"
		rm -f "${aws_error_file}"
		log_error "AWS CLI call failed"
		if [[ -n "${aws_error}" ]]; then
			log_error "${aws_error}"
		fi
		return 1
	fi
	rm -f "${aws_error_file}"
	printf '%s' "${token_output}"
}

log_aws_context() {
	if command -v aws >/dev/null 2>&1; then
		log "Using $(aws --version 2>&1)"
	fi

	log "  domain:       ${AWS_CODEARTIFACT_DOMAIN:-<not set>}"
	log "  domain-owner: ${AWS_CODEARTIFACT_DOMAIN_OWNER:-<not set>}"
	log "  region:       ${AWS_CODEARTIFACT_REGION:-<not set>}"

	local key_id=""
	local key_source=""
	if [[ -n "${AWS_CODEARTIFACT_ACCESS_KEY_ID:-}" ]]; then
		key_id="${AWS_CODEARTIFACT_ACCESS_KEY_ID}"
		key_source="AWS_CODEARTIFACT_ACCESS_KEY_ID"
	elif [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
		key_id="${AWS_ACCESS_KEY_ID}"
		key_source="AWS_ACCESS_KEY_ID"
	fi

	if [[ -n "${key_id}" ]]; then
		log "  credentials:  ${key_source} is set (key ID: ${key_id:0:8}...)"
		if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
			log "  credentials:  AWS_SESSION_TOKEN is set (temporary credentials)"
		fi
	else
		log "  credentials:  no access key set — relying on instance profile or ~/.aws"
	fi
	return 0
}

write_export_script() {
	local destination="${1:?destination is required}"
	local normalized_index_name="${2:?normalized index name is required}"
	local token="${3:?token is required}"

	{
		printf '#!/usr/bin/env bash\n'
		printf 'export UV_INDEX_%s_USERNAME=%q\n' "${normalized_index_name}" "aws"
		printf 'export UV_INDEX_%s_PASSWORD=%q\n' "${normalized_index_name}" "${token}"
	} >"${destination}"

	chmod +x "${destination}"
	return 0
}

validate_token() {
	local token="${1:-}"

	if [[ -z "${token}" || "${token}" == "None" ]]; then
		log_error "Failed to fetch a valid AWS CodeArtifact authorization token"
		return 1
	fi
}
