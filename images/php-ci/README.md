# php-ci

`ghcr.io/phase2/php-ci:8.3`, `:8.4` and `:8.5`: the CI job container for PHP projects. It is
[ci-tools](../ci-tools/README.md) plus PHP CLI and Composer, so a PHP job also has kubectl, helm,
kustomize, aws, Node and the rest.

```yaml
jobs:
  test:
    runs-on: ubuntu-24.04
    container:
      image: ghcr.io/phase2/php-ci:8.4
    steps:
      - uses: actions/checkout@<sha> # vX
      - run: composer install --no-interaction
      - run: vendor/bin/phpunit
```

Like ci-tools, it runs as uid 1000 with no sudo, so the mounted workspace must be writable by
uid 1000.

## Tools

Everything in [ci-tools](../ci-tools/README.md), plus:

| Tool       | Source                                                                              | Notes                                                                                                            |
| ---------- | ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| PHP CLI    | Debian for 8.4; [packages.sury.org](https://packages.sury.org/php/) for 8.3 and 8.5 | one PHP version per tag                                                                                          |
| Composer 2 | getcomposer.org                                                                     | pinned by `COMPOSER_VERSION` in `images/_shared/install-composer.sh`, checked against the release's `.sha256sum` |

### PHP extensions

apcu, bcmath, bz2, calendar, ctype, curl, dom, exif, ffi, fileinfo, ftp, gd, gettext, gnupg,
iconv, igbinary, imagick, intl, ldap, mbstring, memcached, msgpack, mysqli, mysqlnd, OPcache,
pcntl, pdo_mysql, pdo_pgsql, pdo_sqlite, pgsql, posix, readline, redis, shmop, simplexml, soap,
sockets, sodium, sqlite3, ssh2, sysvmsg, sysvsem, sysvshm, tokenizer, xml, xmlreader, xmlwriter,
xsl, zip, plus PHP's always-on core extensions.

**Xdebug** is installed but not loaded. php-ci has no entrypoint toggle, so load it per command,
for example for coverage:

```sh
php -d zend_extension=xdebug -d xdebug.mode=coverage vendor/bin/phpunit --coverage-clover clover.xml
```

The extension list is shared with [php-devcloud](../php-devcloud/README.md) and lives in
`images/_shared/install-php.sh`.

## Details worth knowing

- **PHP settings** are Debian's CLI defaults (`/etc/php/<version>/cli/php.ini`), so
  `memory_limit` is `-1`. Unlike php-devcloud there are no image defaults or project overrides;
  pass `-d` flags or a `PHPRC` if a job needs different settings.
- **PATH** starts with `/var/www/vendor/bin` and `/home/docker/.composer/vendor/bin`, and
  `COMPOSER_HOME=/home/docker/.composer`.
- **Where PHP comes from.** Debian trixie ships PHP 8.4 only. For 8.3 and 8.5 the build adds the
  sury.org apt repository and fails unless its signing key has the expected fingerprint.
- **Extra extensions** need a derived image, because there is no sudo at run time:

  ```dockerfile
  FROM ghcr.io/phase2/php-ci:8.4
  USER root
  RUN apt-get update && apt-get install -y --no-install-recommends php8.4-pcov \
   && rm -rf /var/lib/apt/lists/*
  USER 1000:1000
  ```

- **Tags.** The moving `8.x` tag follows the latest build; each build also gets an immutable
  `8.x-YYYYMMDD-<sha>` tag for pinning.

## Tests

php-ci runs the base and ci-tools structure tests plus the shared PHP test
(`images/_shared/structure-test.php.yaml`), which checks the PHP version, the main extensions,
that Xdebug is installed but off, Composer and `PATH`.
