# Heroku Buildpack: AWS CodeArtifact for `uv`

Classic Heroku buildpack that fetches an AWS CodeArtifact token during build
and exposes it to downstream Python build steps using `uv` named-index
environment variables.

This buildpack is intended for Python apps that install private packages from
AWS CodeArtifact with `uv`.

## What it exports

During `bin/compile`, the buildpack writes an `export` script that sets:

- `UV_INDEX_<NORMALIZED_NAME>_USERNAME=aws`
- `UV_INDEX_<NORMALIZED_NAME>_PASSWORD=<token>`

Example normalization:

- `codeartifact` -> `UV_INDEX_CODEARTIFACT_USERNAME`
- `private-prod` -> `UV_INDEX_PRIVATE_PROD_USERNAME`

## Intended buildpack order

1. `https://github.com/timanovsky/subdir-heroku-buildpack`
2. `https://github.com/heroku/heroku-buildpack-awscli.git`
3. `https://github.com/wiphoo/Heroku-Buildpack-AWS_CodeArtifact_UV.git`
4. `heroku/python`

AWS credentials must already be available to the AWS CLI. This buildpack is
designed to run after `heroku-buildpack-awscli`.

## Required config vars

- `AWS_CODEARTIFACT_DOMAIN`
- `AWS_CODEARTIFACT_DOMAIN_OWNER`
- `AWS_CODEARTIFACT_REGION`
- `AWS_CODEARTIFACT_REPOSITORY`

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

## Local development

Requirements:

- `shellcheck`
- `shfmt`
- `bats`

Commands:

```bash
make
make help
make check
make lint
make test
make ci
```
