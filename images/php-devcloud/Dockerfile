# syntax=docker/dockerfile:1.28
# check=error=true
#
# php-devcloud: the PHP-FPM sidecar of devcloud preview pods. base + PHP CLI/FPM, Composer,
# MySQL client and build tools. Built through docker-bake.hcl (`FROM base` and the `shared`
# scripts are named contexts).
#
# Starts as root with passwordless sudo for `docker`: devcloud tooling runs `runuser -u docker`
# as root and `sudo` as uid 1000. Not meant as a production runtime.

# hadolint ignore=DL3006
FROM base
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Everything that does not depend on PHP comes first, so all PHP versions share this layer.
# build-essential + python3: native npm modules (node-gyp) built in the pod.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-update-retry
apt-get install -y --no-install-recommends \
  build-essential ghostscript imagemagick mariadb-client msmtp pv python3 sqlite3 sudo webp
# sudo keeps the image's environment, so `sudo php`/`sudo su` still read the image and project
# PHP settings, and `sudo drush`/`sudo yarn` still find vendor/bin and Node.
cat > /etc/sudoers.d/docker <<'SUDOERS'
docker ALL=(ALL) NOPASSWD:ALL
Defaults !secure_path
Defaults env_keep += "PATH NVM_DIR PHP_INI_SCAN_DIR PHP_OVERRIDES_DIR MSMTP_HOST MSMTP_PORT"
Defaults env_keep += "XDEBUG_ENABLED XDEBUG_MODE XDEBUG_CLIENT_HOST XDEBUG_CLIENT_PORT"
SUDOERS
chmod 0440 /etc/sudoers.d/docker
install -d -o 1000 -g 1000 -m 0775 /run/php-runtime /run/php-runtime/conf.d /run/php-runtime/fpm.d
rm -rf /var/log/*.log /var/log/apt /tmp/*
EOF

ARG PHP_VERSION=8.4
# Debian's default php-fpm.conf points at the image's, so a bare `php-fpm` (e.g. a restart
# via `sudo su`) gets the same pool as the entrypoint.
# Strip setuid/setgid from everything except sudo (su needs no setuid when run via sudo).
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=bind,from=shared,source=install-php.sh,target=/usr/local/lib/install-php.sh \
    bash /usr/local/lib/install-php.sh fpm \
 && ln -sf /usr/local/etc/php-fpm/php-fpm.conf "/etc/php/${PHP_VERSION}/fpm/php-fpm.conf" \
 && find / -xdev -perm /6000 -type f ! -path /usr/bin/sudo -exec chmod a-s {} +

RUN --mount=type=bind,from=shared,source=install-composer.sh,target=/usr/local/lib/install-composer.sh \
    bash /usr/local/lib/install-composer.sh

COPY --link rootfs/ /

ENV TERM=xterm \
    PROJECT_ROOT=/var/www \
    PHP_INI_SCAN_DIR=:/usr/local/etc/php/conf.d:/run/php-runtime/conf.d \
    MSMTP_HOST=mail \
    MSMTP_PORT=1025 \
    XDEBUG_ENABLED=0 \
    XDEBUG_MODE=debug \
    XDEBUG_CLIENT_HOST=host.docker.internal \
    XDEBUG_CLIENT_PORT=9003 \
    COMPOSER_HOME=/home/docker/.composer \
    PATH=/var/www/vendor/bin:/home/docker/.composer/vendor/bin:${PATH}

EXPOSE 9000
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint"]
CMD ["php-fpm"]

LABEL org.opencontainers.image.title="php-devcloud" \
      org.opencontainers.image.description="Phase2 PHP ${PHP_VERSION} FPM sidecar for devcloud preview environments (Debian trixie-slim)"
