# AWS CodeArtifact for `uv`

Classic Heroku buildpack for Cedar-generation apps that fetches an AWS
CodeArtifact token during build and exposes it to downstream build steps using
`uv` named-index environment variables.

This buildpack is intended for Python apps that install private packages from
AWS CodeArtifact with `uv`.

## What it exports

During `bin/compile`, the buildpack writes an `export` script that sets:

- `UV_INDEX_<NORMALIZED_NAME>_USERNAME=aws`
- `UV_INDEX_<NORMALIZED_NAME>_PASSWORD=<token>`

Example normalization:

- `codeartifact` -> `UV_INDEX_CODEARTIFACT_USERNAME`
- `private-prod` -> `UV_INDEX_PRIVATE_PROD_USERNAME`

## Compatibility

This repository is primarily intended for classic Heroku buildpack usage on
Cedar-generation apps.

Detection is strict. The app must contain a `pyproject.toml` file with a
`[[tool.uv.index]]` block or Heroku will report:

```text
App not compatible with buildpack
```

This buildpack is intended to be added alongside your primary language
buildpack, not used as a replacement for it.

## Intended classic buildpack order

1. `https://github.com/timanovsky/subdir-heroku-buildpack`
2. `https://github.com/heroku/heroku-buildpack-awscli.git`
3. `https://github.com/wiphoo/Heroku-Buildpack-AWS_CodeArtifact_UV.git`
4. `heroku/python`

## Required config vars

- `AWS_CODEARTIFACT_DOMAIN`
- `AWS_CODEARTIFACT_DOMAIN_OWNER`
- `AWS_CODEARTIFACT_REGION`

## AWS credentials

The buildpack uses the AWS CLI to call `codeartifact get-authorization-token`.
You must supply credentials via Heroku config vars before the build runs.

**Option A — custom-namespaced vars (recommended)**

Use these to avoid conflicts with other buildpacks or tools that read the
standard `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` names:

- `AWS_CODEARTIFACT_ACCESS_KEY_ID`
- `AWS_CODEARTIFACT_SECRET_ACCESS_KEY`

The buildpack maps these to the standard names before calling the AWS CLI.

**Option B — standard AWS vars**

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` _(required only when using temporary/assumed-role credentials)_

When `AWS_CODEARTIFACT_ACCESS_KEY_ID` is set it takes precedence over
`AWS_ACCESS_KEY_ID`.

## Optional config vars

- `UV_CODEARTIFACT_INDEX_NAME`
  - Default: `codeartifact`
  - Set this explicitly so it matches the named index in your
    `pyproject.toml`

## `pyproject.toml` example

```toml
[[tool.uv.index]]
name = "codeartifact"
url = "https://example.invalid/pypi/private/simple/"
default = false

[project]
name = "example-app"
version = "0.1.0"
dependencies = ["private-package"]
```

The buildpack only handles authentication. Your named `uv` index definition
still belongs in `pyproject.toml`.

## Local `pack build` usage

`pack build` support in this repository is a local verification harness for the
buildpack logic. It is not the supported way to consume this repository on
Heroku Cedar apps.

Example:

```bash
pack build example-app \
  --path /path/to/app \
  --builder heroku/builder:24 \
  --buildpack /path/to/Heroku-Buildpack-AWS_CodeArtifact_UV \
  --env AWS_CODEARTIFACT_DOMAIN=example \
  --env AWS_CODEARTIFACT_DOMAIN_OWNER=123456789012 \
  --env AWS_CODEARTIFACT_REGION=us-east-1
```

For deterministic local testing without real AWS access, the integration
harness uses the test-only environment override
`BUILDPACK_TEST_AWS_CODEARTIFACT_TOKEN`.

For Heroku Fir/CNB apps, do not configure this repository as a classic
Git-URL buildpack. Use Heroku CNB configuration through `project.toml`
instead.

## Local development

Requirements:

- `shellcheck`
- `shfmt`
- `bats`
- `pack`
- `docker`

Commands:

```bash
make
make tools
make check
make lint
make test
make test-integration-generic
make test-integration-heroku
make ci
```
