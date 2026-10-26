# Phase2 Debian images

php-devcloud has a runtime contract that devcloud tooling depends on (see its section in
`README.md`); `images/php-devcloud/tests/compat-test.sh` encodes it. Keep that test passing when
changing an image's users, sudo, installed tools or update policy.

## Building and done

Build through bake: `make build IMAGE=<image> [PHP=<x.y>]`. `FROM base` and `FROM ci-tools` are
bake named contexts, so a plain `docker build` cannot resolve them.

A change is done when `make lint` passes and `make build test scan` passes for every image it
reaches: base feeds every image except httpd-devcloud, and ci-tools feeds php-ci.

httpd-devcloud has a runtime contract too (its README); `images/httpd-devcloud/tests/compat-test.sh`
encodes it.

## Dockerfile gotchas

- Each `.dockerignore` is an allowlist: a file the Dockerfile newly `COPY`s needs a `!path` entry.
- Tool versions: Renovate's regex (`renovate.json`) matches a `# renovate: datasource=... depName=...`
  comment on the line directly above `ARG <NAME>_VERSION=`. Match that shape exactly, or the tool
  silently stops getting updates.
- Downloaded binaries are verified against the checksum or signature their project publishes, in
  the `fetch` stage, then `COPY --link --chown=0:0` into the image.
- A new tool gets a check in the image's `tests/structure-test.yaml` and a line in its `README.md`.
- OCI title and description labels come from each Dockerfile; CI publishes with
  `set-meta-labels: false`.

## Intentional choices (keep them)

- The Debian base (`debian:trixie-slim`) and apt packages stay unpinned: the weekly no-cache
  rebuild picks up security fixes and Trivy gates it. Hence hadolint DL3008 is ignored.
- php-devcloud defaults to root and `docker` has passwordless sudo, because devcloud tooling
  depends on both. ci-tools and php-ci run as uid 1000 without sudo.
- Images are full Debian with broad toolsets: the tool contract outranks image size.
- httpd-devcloud builds FROM the official `httpd:2.4.x-trixie` image, not base or
  `debian:trixie-slim`: Apache comes from upstream as docksal/apache's did, and needs neither Node
  nor the docker user. The tag is pinned in an `ARG` Renovate tracks (kept on 2.4 and trixie by
  `renovate.json`), with no digest, so the weekly rebuild gets upstream's rebuilds. It runs
  `apt-get upgrade` because upstream's Debian packages otherwise only refresh when upstream rebuilds.
- httpd-devcloud makes its self-signed certificate at container start, not at build time: a key in
  the image is a Trivy secret finding and would be the same for everyone pulling a public image.

## Build secrets

Credentials reach a build only through `RUN --mount=type=secret` or `--mount=type=ssh`, read inside
that one `RUN`. `ARG`, `ENV` and `COPY` persist into layers or the build cache, so they never carry
credentials. For SSH, write the provider's published host keys into `known_hosts`.
