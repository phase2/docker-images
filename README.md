# phase2/docker-images

Container images for Phase2's devcloud preview environments and CI. Together they replace [`phase2/docker-cli`](https://github.com/phase2/docker-cli).

| Image | Use it for | Tags |
|---|---|---|
| `ghcr.io/phase2/php-devcloud` | the PHP-FPM sidecar in devcloud pods; `FROM` for project images | `8.3`, `8.4`, `8.5`, plus immutable `8.x-YYYYMMDD-<sha>` |
| `ghcr.io/phase2/php-ci` | GitHub Actions job container for PHP projects | `8.3`, `8.4`, `8.5`, plus immutable `8.x-YYYYMMDD-<sha>` |
| `ghcr.io/phase2/ci-tools` | GitHub Actions job container without PHP | `1`, plus immutable `1-YYYYMMDD-<sha>` |

All images are linux/amd64 and linux/arm64, Debian trixie-slim based, with the `docker` user at 1000:1000 and code at `/var/www`. There is no `latest` tag.

```
images/
  base/           internal foundation: docker user, utilities, nvm + Node 24 (not published)
  ci-tools/       base + kubectl, helm (helm3), kustomize, aws, htpasswd
  php-ci/         ci-tools + PHP CLI + Composer
  php-devcloud/   base + PHP CLI/FPM, Composer, MySQL client, build tools; rootfs/ and tests/
  _shared/        install-php.sh + install-composer.sh (used by both PHP images) + shared structure tests
docker-bake.hcl   every image and the PHP matrix; named contexts wire the images together
Makefile          lint / build / test / scan, used locally and in CI
```

Each image has a README with its tools, settings and details: [base](images/base/README.md), [ci-tools](images/ci-tools/README.md), [php-ci](images/php-ci/README.md), [php-devcloud](images/php-devcloud/README.md).

## Local workflow

```sh
mise install                                   # once: shellcheck, container-structure-test, lefthook
lefthook install                               # once: pre-commit hook (lint + gitleaks on staged changes)
make builder                                   # once: docker-container builder (bake needs it)
make lint                                      # hadolint, shellcheck, BuildKit checks
make repo-lint                                 # actionlint, gitleaks
make build test scan IMAGE=php-devcloud PHP=8.4
make build test scan IMAGE=php-ci PHP=8.5
make build test scan IMAGE=ci-tools
```

Prerequisites: Docker with buildx and [mise](https://mise.jdx.dev). `mise.toml` pins the host tools, `mise.lock` their checksums, and CI installs from the same files. hadolint, Trivy, actionlint and gitleaks run from digest-pinned images.

Images are only buildable through bake. `FROM base` and `FROM ci-tools` are bake named contexts, not registry images.

## php-devcloud at runtime

- **Startup.** With no command it runs `php-fpm` on port 9000. The FPM master runs as root and the workers as `docker`, with `clear_env = no`.
- **User and sudo.** The image starts as root and `docker` has passwordless sudo, because devcloud tooling runs `runuser -u docker` as root and `sudo` as uid 1000. It is not meant as a production runtime.
- **Project overrides.** Set `PHP_OVERRIDES_DIR` to a directory, typically in the project checkout, and the entrypoint applies it at start. When it is unset there are no project overrides, and the entrypoint logs a notice saying so. The directory holds:
  - `*.ini` applies to both the CLI and FPM.
  - `php-fpm.conf` holds `[www]` pool directives, e.g. `php_admin_value[memory_limit] = 2048M`.
- **Memory.** FPM defaults to `memory_limit = 1024M` and the CLI to `-1`.
- **Xdebug.** Set `XDEBUG_ENABLED=1` to turn it on. `XDEBUG_MODE`, `XDEBUG_CLIENT_HOST` and `XDEBUG_CLIENT_PORT` configure it.
- **Node.**
  - nvm lives at `NVM_DIR=/home/docker/.nvm`, with Node 24 as the default.
  - `nvm install` fetches whatever a project's `.nvmrc` asks for and adds yarn 1 to it automatically.

## Updating

- **Debian packages** come in through the weekly scheduled rebuild (no cache) and are gated on Trivy.
- **Tool versions** are `ARG`s (or variables in the `images/_shared/*.sh` scripts) with `# renovate:` comments.
  - Renovate opens the bump PRs. Patch and minor bumps auto-merge on green CI.
  - Builds verify each download against the checksum file its project publishes.
- **Breaking changes** to `ci-tools` (a removed tool, for example) bump `CI_TOOLS_MAJOR` in `docker-bake.hcl`; CI reads the variants and their tags from there. They are recorded in `CHANGELOG.md`.

## Publishing

`.github/workflows/images.yml` runs lint, then builds and tests every variant on native amd64 and arm64 runners. On `main`, the weekly schedule and manual runs it then publishes through [`docker/github-builder`](https://docs.docker.com/build/ci/github-actions/github-builder/). That adds an SBOM, SLSA provenance and signed attestations.

- **Required check.** The `ci` job passes only when lint and every test variant pass. Make it the one required status check on `main`; the test jobs' names come from `docker-bake.hcl`, so they can't be listed individually.
- **Code scanning.** Each test job uploads Trivy's fixable HIGH/CRITICAL findings, including vendored npm, Go and PHP dependencies, to the repository's code scanning alerts, one category per variant and architecture. Pull requests from forks skip the upload.

GHCR packages must be **public** for devcloud to pull them, because the pod pulls anonymously. Set this once per package after its first publish.
