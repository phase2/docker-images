# php-devcloud

`ghcr.io/phase2/php-devcloud:8.3`, `:8.4` and `:8.5`: the PHP-FPM container in devcloud preview
pods, and the image projects build `FROM` when they need more. It builds on
[base](../base/README.md), not ci-tools, so it has no Kubernetes or cloud tools.

**Not a production runtime.** It starts as root and `docker` has passwordless sudo, because the
devcloud tooling that runs commands in the pod relies on both.

## Tools

Everything in [base](../base/README.md) (git, rsync, curl, jq, Node 24 with nvm and yarn 1, and
more), plus:

| Area                 | Tools                                                                                                |
| -------------------- | ---------------------------------------------------------------------------------------------------- |
| PHP                  | PHP CLI and PHP-FPM, Composer 2, the same extensions as [php-ci](../php-ci/README.md#php-extensions) |
| Database             | `mysql` and `mysqldump` (MariaDB client), `sqlite3`                                                  |
| Mail                 | `msmtp`, wired up as PHP's `sendmail_path`                                                           |
| Images and documents | ImageMagick (`convert`), Ghostscript (`gs`), `cwebp`                                                 |
| Native npm modules   | `build-essential` (gcc, g++, make), `python3`                                                        |
| Other                | `pv`, `sudo`                                                                                         |

## Runtime

With no command, the entrypoint applies runtime PHP settings and runs php-fpm in the foreground,
listening on port 9000. Any other command runs after the same setup, so
`docker run <image> php -v` also sees the project's settings.

```
tini (PID 1)
└─ docker-entrypoint: write /run/php-runtime/{conf.d,fpm.d}, then exec
   └─ php-fpm master (root)
      └─ pool [www] workers (docker)
```

### Environment variables

| Variable                    | Default                | Effect                                                                                                                    |
| --------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `PHP_OVERRIDES_DIR`         | unset                  | Directory of project PHP settings (see below). Unset means none, and the entrypoint logs a notice when it starts php-fpm. |
| `XDEBUG_ENABLED`            | `0`                    | `1` loads Xdebug at start                                                                                                 |
| `XDEBUG_MODE`               | `debug`                | `xdebug.mode`                                                                                                             |
| `XDEBUG_CLIENT_HOST`        | `host.docker.internal` | `xdebug.client_host`                                                                                                      |
| `XDEBUG_CLIENT_PORT`        | `9003`                 | `xdebug.client_port`                                                                                                      |
| `MSMTP_HOST` / `MSMTP_PORT` | `mail` / `1025`        | where PHP's mail goes, for example a Mailpit service                                                                      |
| `DEBUG`                     | unset                  | non-zero makes the entrypoint log what it applied                                                                         |

### Project PHP settings

Point `PHP_OVERRIDES_DIR` at a directory, usually inside the project checkout. At start the
entrypoint applies:

- **`*.ini`**: symlinked into the scan directory, so they apply to the CLI and FPM. The CLI sees
  edits immediately; FPM sees them after a reload.
- **`php-fpm.conf`**: pool directives for `[www]` (the header is optional), for example
  `php_admin_value[memory_limit] = 2048M`.

FPM's `memory_limit` can only be changed in `php-fpm.conf`, because the pool's value beats every
ini file. Everything else can go in either.

### Defaults

| Setting                                 | CLI                             | FPM                       |
| --------------------------------------- | ------------------------------- | ------------------------- |
| `memory_limit`                          | `-1`                            | `1024M` (set in the pool) |
| `max_execution_time`                    | 0 (the CLI is always unlimited) | 300                       |
| `upload_max_filesize` / `post_max_size` | 500M                            | 500M                      |
| `max_input_vars`                        | 2000                            | 2000                      |
| `display_errors`, `error_reporting`     | On, `E_ALL`                     | On, `E_ALL`               |
| `date.timezone`                         | UTC                             | UTC                       |

The FPM pool uses `pm = dynamic` with up to 10 children, answers `/ping`, discards the access log,
and sends worker output and errors to the container log. `clear_env = no` passes the pod's
environment (database credentials, secrets) through to PHP.

## Details worth knowing

- **Users.** The image's default user is root, so `runuser -u docker -- <cmd>` works from
  `kubectl exec`. `docker` (1000:1000) has passwordless sudo, so `sudo chown` works from a
  container that runs as uid 1000.
- **sudo keeps the environment.** sudoers keeps `PATH`, `NVM_DIR`, `PHP_INI_SCAN_DIR`,
  `PHP_OVERRIDES_DIR`, `MSMTP_*` and `XDEBUG_*`, and drops `secure_path`. So `sudo php`,
  `sudo drush` and `sudo su -c ...` see the same PHP settings, vendor binaries and Node.
- **Only sudo is setuid.** The build strips setuid and setgid from every other binary. `sudo su`
  still works, because `su` then runs as root.
- **Reloading FPM.** `kill -USR2 1` sends USR2 to tini, which passes it to the php-fpm master, and
  the master reloads its workers. Debian's own `php-fpm.conf` points at this image's config, so a
  bare `php-fpm` started by hand gets the same pool.
- **Mail.** `sendmail_path` runs `msmtp` against `$MSMTP_HOST:$MSMTP_PORT`, so mail goes to a
  catcher service instead of out to the internet.
- **No systemd.** php-fpm's packaging asks for systemd's tmpfiles; the standalone
  `systemd-standalone-tmpfiles` package satisfies that without installing systemd.
- **Layer sharing.** Everything that doesn't depend on PHP is installed before PHP, so the three
  PHP versions share that layer.

## Building a project image

```dockerfile
FROM ghcr.io/phase2/php-devcloud:8.4
RUN apt-update-retry \
 && apt-get install -y --no-install-recommends php8.4-pcov \
 && rm -rf /var/lib/apt/lists/*
```

The image is already root at build time, and Debian, `apt-get`, the `docker` user at 1000:1000
and `/var/www` are part of its contract.

## Tests

- `tests/structure-test.yaml`: metadata, the FPM config, sudo, the tools above, and that no
  Kubernetes or cloud tools or systemd are present. The base and shared PHP structure tests also
  run against this image.
- `tests/compat-test.sh`: starts real containers and checks the runtime behaviour end to end:
  `/ping`, users and sudo, pod environment reaching FPM workers, memory limits, an `.nvmrc`
  install, project overrides through FPM, CLI, `sudo` and `sudo su`, and the Xdebug toggle.
