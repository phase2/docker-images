#!/usr/bin/env bash
# Install PHP ${PHP_VERSION} and the common extension set into a Debian trixie image.
# Composer comes from install-composer.sh, in its own layer.
# Debian ships one PHP version (DEBIAN_PHP_VERSION); every other version comes from
# packages.sury.org, whose signing key fingerprint is pinned below.
#
# Needs base's apt-update-retry.
#
# Usage (as root, from a Dockerfile RUN with this file bind-mounted):
#   PHP_VERSION=8.4 install-php.sh cli   # PHP CLI only
#   PHP_VERSION=8.4 install-php.sh fpm   # PHP CLI + php-fpm (at /usr/local/sbin/php-fpm)
set -euo pipefail

flavor="${1:?usage: install-php.sh <cli|fpm>}"
: "${PHP_VERSION:?PHP_VERSION must be set}"

DEBIAN_PHP_VERSION=8.4
SURY_SIGNER_FPR=15058500A0235D97F5D10063B188E2B695BD4743

EXTENSIONS=(
  apcu bcmath bz2 curl gd gnupg imagick intl ldap mbstring memcached mysql opcache pgsql
  readline redis soap sqlite3 ssh2 xdebug xml xsl zip
)

export DEBIAN_FRONTEND=noninteractive

if [[ "${PHP_VERSION}" != "${DEBIAN_PHP_VERSION}" ]]; then
  curl -fsSL --retry 5 --proto '=https' -o /tmp/sury.gpg https://packages.sury.org/php/apt.gpg
  gpg --show-keys --with-colons /tmp/sury.gpg | awk -F: '/^fpr/{print $10}' | grep -qx "${SURY_SIGNER_FPR}"
  install -m 0644 /tmp/sury.gpg /usr/share/keyrings/sury-php.gpg
  echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ trixie main" \
    > /etc/apt/sources.list.d/sury-php.list
  rm -f /tmp/sury.gpg
fi
apt-update-retry

p="php${PHP_VERSION}"
packages=("${p}-cli")
for ext in "${EXTENSIONS[@]}"; do
  # PHP >= 8.5 compiles OPcache into core; there is no separate package.
  if [[ "${ext}" == opcache ]] && dpkg --compare-versions "${PHP_VERSION}" ge 8.5; then continue; fi
  packages+=("${p}-${ext}")
done
# php-fpm depends on `systemd | systemd-tmpfiles`; the standalone tmpfiles package satisfies it
# without installing all of systemd.
[[ "${flavor}" == fpm ]] && packages+=("${p}-fpm" systemd-standalone-tmpfiles)
apt-get install -y --no-install-recommends "${packages[@]}"

# Xdebug is installed but disabled; images enable it at runtime (XDEBUG_ENABLED=1).
phpdismod -v ALL -s ALL xdebug

if [[ "${flavor}" == fpm ]]; then
  ln -sf "/usr/sbin/php-fpm${PHP_VERSION}" /usr/local/sbin/php-fpm
  # Images ship their own pool config.
  rm -f "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
fi

rm -rf /var/log/*.log /var/log/apt /tmp/*
