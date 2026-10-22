#!/usr/bin/env bash
# Install Composer, verified against the checksum getcomposer.org publishes for the release.
# Kept apart from install-php.sh so a Composer bump rebuilds only this layer.
# Usage (as root, from a Dockerfile RUN with this file bind-mounted): install-composer.sh
set -euo pipefail

# renovate: datasource=github-releases depName=composer/composer
COMPOSER_VERSION=2.10.3

cd /tmp
curl -fsSL --retry 5 --retry-all-errors --proto '=https' -o composer.phar "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar"
curl -fsSL --retry 5 --retry-all-errors --proto '=https' -o composer.phar.sha256sum "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar.sha256sum"
sha256sum --strict -c composer.phar.sha256sum
install -m 0755 composer.phar /usr/local/bin/composer
rm -f composer.phar composer.phar.sha256sum
