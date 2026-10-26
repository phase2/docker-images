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
| PHP CLI    | [packages.sury.org](https://packages.sury.org/php/)                                 | one PHP version per tag                                                                                          |
| Composer 2 | getcomposer.org                                                                     | pinned by `COMPOSER_VERSION` in `images/_shared/install-composer.sh`, checked against the release's `.sha256sum` |

### PHP extensions

apcu, bcmath, bz2, calendar, ctype, curl, dom, exif, ffi, fileinfo, ftp, gd, gettext, gmp, gnupg,
iconv, igbinary, imagick, intl, ldap, mbstring, memcached, msgpack, mysqli, mysqlnd, OPcache,
pcntl, pdo_mysql, pdo_pgsql, pdo_sqlite, pgsql, posix, readline, redis, shmop, simplexml, soap,
sockets, sodium, sqlite3, ssh2, sysvmsg, sysvsem, sysvshm, tidy, tokenizer, uploadprogress, xml,
xmlreader, xmlwriter, xsl, yaml, zip, plus PHP's always-on core extensions.

gmp, tidy and yaml are loaded on both Acquia and Pantheon, and uploadprogress on Pantheon (Drupal's
status report checks for it). yaml matters most: Drupal core parses YAML with it whenever it is
loaded (`YamlPecl`), so an image without it would parse config differently from the hosting
platform.

**Xdebug** is installed but not loaded. php-ci has no entrypoint toggle, so load it per command,
for example for coverage:

```sh
php -d zend_extension=xdebug -d xdebug.mode=coverage vendor/bin/phpunit --coverage-clover clover.xml
```

The extension list is shared with [php-devcloud](../php-devcloud/README.md) and lives in
`images/_shared/install-php.sh`.

## Details worth knowing

- **PHP settings** are Debian's CLI defaults (`/etc/php/<version>/cli/php.ini`), so
  `memory_limit` is `-1`. The one exception is `zend.assertions = 1`, so test suites run
  `assert()`: Debian's production `-1` compiles assertions out, and nothing can turn them back on
  at runtime. Unlike php-devcloud there are no project overrides; pass `-d` flags or a `PHPRC` if
  a job needs different settings.
- **PATH** starts with `/var/www/vendor/bin` and `/home/docker/.composer/vendor/bin`, and
  `COMPOSER_HOME=/home/docker/.composer`.
- **Where PHP comes from.** Every version, 8.4 included, comes from the sury.org apt repository,
  so all tags share the same packaging and extension builds. The build fails unless sury's
  signing key has the expected fingerprint, and an apt pin keeps `php*` packages on sury even
  when Debian's own 8.4 packages are newer, including in derived images.
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
