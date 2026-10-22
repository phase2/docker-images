# syntax=docker/dockerfile:1.28
# check=error=true
#
# php-ci: PHP CI job container. ci-tools + PHP CLI and Composer. Runs as uid 1000, no sudo.
# Built through docker-bake.hcl (`FROM ci-tools` and the `shared` scripts are named contexts).

# hadolint ignore=DL3006
FROM ci-tools
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ARG PHP_VERSION=8.4

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=bind,from=shared,source=install-php.sh,target=/usr/local/lib/install-php.sh \
    bash /usr/local/lib/install-php.sh cli \
 && find / -xdev -perm /6000 -type f -exec chmod a-s {} +

RUN --mount=type=bind,from=shared,source=install-composer.sh,target=/usr/local/lib/install-composer.sh \
    bash /usr/local/lib/install-composer.sh

ENV COMPOSER_HOME=/home/docker/.composer \
    PATH=/var/www/vendor/bin:/home/docker/.composer/vendor/bin:${PATH}

USER 1000:1000

LABEL org.opencontainers.image.title="php-ci" \
      org.opencontainers.image.description="Phase2 PHP ${PHP_VERSION} CI job container: ci-tools + PHP CLI and Composer (Debian trixie-slim)"
