# phase2/docker-images

Container images for Phase2's devcloud preview environments and CI. Together they replace [`phase2/docker-cli`](https://github.com/phase2/docker-cli).

| Image | Use it for | Tags |
|---|---|---|
| `ghcr.io/phase2/php-devcloud` | the PHP-FPM sidecar in devcloud pods; `FROM` for project images | `8.3`, `8.4`, `8.5`, plus immutable `8.x-YYYYMMDD-<sha>` |
| `ghcr.io/phase2/php-ci` | GitHub Actions job container for PHP projects | `8.3`, `8.4`, `8.5`, plus immutable `8.x-YYYYMMDD-<sha>` |
| `ghcr.io/phase2/ci-tools` | GitHub Actions job container without PHP | `1`, plus immutable `1-YYYYMMDD-<sha>` |
| `ghcr.io/phase2/httpd-devcloud` | the Apache web container in devcloud pods, in front of php-devcloud | `2.4`, plus immutable `2.4-YYYYMMDD-<sha>` |

All images are linux/amd64 and linux/arm64, with code at `/var/www`. All but httpd-devcloud are Debian trixie-slim based, with the `docker` user at 1000:1000; httpd-devcloud builds on the official Debian trixie `httpd` image. There is no `latest` tag.

```
images/
  base/           internal foundation: docker user, utilities, nvm + Node 24 (not published)
  ci-tools/       base + kubectl, helm (helm3), kustomize, aws, htpasswd
  php-ci/         ci-tools + PHP CLI + Composer
  php-devcloud/   base + PHP CLI/FPM, Composer, MySQL client, build tools; rootfs/ and tests/
  httpd-devcloud/ official httpd:2.4 (Debian trixie) + devcloud vhosts; not FROM base
  _shared/        install-php.sh + install-composer.sh (used by both PHP images) + shared structure tests
docker-bake.hcl   every image and the PHP matrix; named contexts wire the images together
Makefile          lint / build / test / scan, used locally and in CI
```

Each image has a README with its tools, settings and details: [base](images/base/README.md), [ci-tools](images/ci-tools/README.md), [php-ci](images/php-ci/README.md), [php-devcloud](images/php-devcloud/README.md), [httpd-devcloud](images/httpd-devcloud/README.md).

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
make build test scan IMAGE=httpd-devcloud
make build-all test-all scan-all               # every image: one bake call, then parallel tests/scans
make build-all NO_CACHE=1                      # ...from scratch, like CI's weekly rebuild
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

## httpd-devcloud at runtime

The Apache container next to php-devcloud in a devcloud pod; its [README](images/httpd-devcloud/README.md) has the full contract, and `images/httpd-devcloud/tests/compat-test.sh` encodes it.

- **Docroot.** `APACHE_DOCUMENTROOT`, else `DOCROOT` (relative paths are under `/var/www`), else `/var/www/docroot`.
- **PHP.** `.php` files that exist go over FastCGI to `APACHE_FCGI_HOST_PORT`, by default `127.0.0.1:9000`.
- **Ports.** 80, and 443 with a self-signed certificate made at start.
- **Project overrides.** `APACHE_OVERRIDES_DIR` names a directory whose `httpd-vhost-overrides.conf` goes last inside both vhosts and whose `httpd-vhosts.conf` goes at server level. When it is unset, a notice is logged.
- **Basic auth.** `APACHE_BASIC_AUTH_USER` and `APACHE_BASIC_AUTH_PASS` together protect the docroot.

## Updating

- **Debian packages** come in through the weekly scheduled rebuild (no cache) and are gated on Trivy. httpd-devcloud runs `apt-get upgrade` on top of the official `httpd` image for the same effect.
- **Apache** is the `httpd:2.4.x-trixie` tag in `images/httpd-devcloud/Dockerfile`; Renovate bumps it within 2.4.
- **Tool versions** are `ARG`s (or variables in the `images/_shared/*.sh` scripts) with `# renovate:` comments.
  - Renovate opens the bump PRs. Patch and minor bumps auto-merge on green CI.
  - Builds verify each download against the checksum file its project publishes.
- **Breaking changes** to `ci-tools` (a removed tool, for example) bump `CI_TOOLS_MAJOR` in `docker-bake.hcl`; CI reads the variants and their tags from there. They are recorded in `CHANGELOG.md`.

## Publishing

`.github/workflows/images.yml` runs lint, then builds and tests every variant on native amd64 and arm64 runners. On `main`, the weekly schedule and manual runs it then publishes through [`docker/github-builder`](https://docs.docker.com/build/ci/github-actions/github-builder/). That adds an SBOM, SLSA provenance and signed attestations.

- **Required check.** The `ci` job passes only when lint and every test variant pass. Make it the one required status check on `main`; the test jobs' names come from `docker-bake.hcl`, so they can't be listed individually.
- **Code scanning.** Each test job uploads Trivy's fixable HIGH/CRITICAL findings, including vendored npm, Go and PHP dependencies, to the repository's code scanning alerts, one category per variant and architecture. Pull requests from forks skip the upload.

GHCR packages must be **public** for devcloud to pull them, because the pod pulls anonymously. Set this once per package after its first publish.
