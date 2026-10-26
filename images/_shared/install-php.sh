#!/usr/bin/env bash
# Install PHP ${PHP_VERSION} and the common extension set into a Debian image.
# Composer comes from install-composer.sh, in its own layer.
# Every PHP version comes from packages.sury.org, whose signing key fingerprint is pinned below,
# so all versions get the same packaging and extension builds, and a Debian release upgrade
# changes no PHP versions. The repo follows the base image's Debian codename.
#
# Needs base's apt-update-retry.
#
# Usage (as root, from a Dockerfile RUN with this file bind-mounted):
#   PHP_VERSION=8.4 install-php.sh cli   # PHP CLI only
#   PHP_VERSION=8.4 install-php.sh fpm   # PHP CLI + php-fpm (at /usr/local/sbin/php-fpm)
set -euo pipefail

flavor="${1:?usage: install-php.sh <cli|fpm>}"
: "${PHP_VERSION:?PHP_VERSION must be set}"

SURY_SIGNER_FPR=15058500A0235D97F5D10063B188E2B695BD4743

EXTENSIONS=(
  apcu bcmath bz2 curl gd gmp gnupg imagick intl ldap mbstring memcached mysql opcache pgsql
  readline redis soap sqlite3 ssh2 tidy uploadprogress xdebug xml xsl yaml zip
)

export DEBIAN_FRONTEND=noninteractive

# shellcheck disable=SC1091
codename="$(. /etc/os-release && echo "${VERSION_CODENAME:?}")"
curl -fsSL --retry 5 --proto '=https' -o /tmp/sury.gpg https://packages.sury.org/php/apt.gpg
# The file must hold sury's key and no other: every primary key in it is trusted for the repo.
[[ "$(gpg --show-keys --with-colons /tmp/sury.gpg | awk -F: '$1 == "pub" {getline; print $10}')" == "${SURY_SIGNER_FPR}" ]]
install -m 0644 /tmp/sury.gpg /usr/share/keyrings/sury-php.gpg
echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ ${codename} main" \
  > /etc/apt/sources.list.d/sury-php.list
# Debian ships its own php<x.y>-* for its default version: prefer sury's even when Debian's is
# newer, so PHP and its extensions never mix sources (here or in derived images' apt installs).
# Libraries sury also rebuilds (libgd3, ...) keep apt's normal newest-wins rule.
cat > /etc/apt/preferences.d/sury-php <<'PREFS'
Package: php*
Pin: origin packages.sury.org
Pin-Priority: 990
PREFS
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

# Run assert() in every SAPI: these are dev and CI images, and Debian's production php.ini (-1)
# compiles assertions out, which nothing can undo at runtime. Later scan dirs can still override.
for confd in "/etc/php/${PHP_VERSION}"/*/conf.d; do
  printf 'zend.assertions = 1\n' > "${confd}/05-assertions.ini"
done

if [[ "${flavor}" == fpm ]]; then
  ln -sf "/usr/sbin/php-fpm${PHP_VERSION}" /usr/local/sbin/php-fpm
  # Images ship their own pool config.
  rm -f "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
fi

rm -rf /var/log/*.log /var/log/apt /tmp/*
