# httpd-devcloud

`ghcr.io/phase2/httpd-devcloud:2.4`: the Apache web container in devcloud preview pods, a
replacement for `docksal/apache:2.4`. It serves the project's docroot from the checkout at
`/var/www` and hands `.php` requests to the [php-devcloud](../php-devcloud/README.md) PHP-FPM
container over FastCGI.

It builds `FROM` the official [`httpd:2.4` image](https://hub.docker.com/_/httpd) on Debian
trixie, not [base](../base/README.md): Apache needs neither the `docker` user nor Node.

## The pod

```
pod (one network namespace)
├─ httpd-devcloud   :80, :443   reads /var/www
├─ php-devcloud     :9000       PHP-FPM, writes /var/www (uid 1000)
└─ database
```

Apache's workers run as `www-data` and only read the checkout, so its files need to be
world-readable, as they are in a normal checkout.

```
httpd-foreground (PID 1): write conf/devcloud-runtime.conf from the environment, then exec
└─ httpd master (root, -DFOREGROUND)
   └─ workers (www-data)
```

## Runtime contract

### Environment variables

| Variable                                            | Default                    | Effect                                                                                                                     |
| --------------------------------------------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `APACHE_DOCUMENTROOT`                               | unset                      | `DocumentRoot`. Wins over `DOCROOT`.                                                                                       |
| `DOCROOT`                                           | `/var/www/docroot`         | `DocumentRoot` when `APACHE_DOCUMENTROOT` is unset. A relative path, such as `web`, is under `/var/www`.                   |
| `APACHE_FCGI_HOST_PORT`                             | `127.0.0.1:9000`           | where `.php` requests go: the PHP-FPM container in the same pod                                                            |
| `APACHE_OVERRIDES_DIR`                              | unset                      | directory of project Apache settings (see below). Unset means none, and a notice is logged at start.                       |
| `APACHE_BASIC_AUTH_USER` / `APACHE_BASIC_AUTH_PASS` | unset                      | when both are set, the docroot requires that login                                                                         |
| `APACHE_SERVERNAME`                                 | the container's hostname   | `ServerName`                                                                                                               |
| `DEBUG`                                             | unset                      | non-zero makes `httpd-foreground` log what it applied                                                                      |

### Ports

- **80**: HTTP, the port the pod's Service sends traffic to.
- **443**: HTTPS with a self-signed certificate, for clients inside the pod such as tests
  against `https://localhost`. TLS 1.2 and 1.3 only, with docksal/apache's cipher settings.
  `httpd-foreground` generates the certificate (`CN=localhost`) when the container starts, so no
  private key ships in this public image. An image built `FROM` this one can provide its own
  `conf/server.crt` and `conf/server.key` instead.

### The default vhost

The `:80` and `:443` vhosts share one configuration, as in docksal/apache:

- `DocumentRoot` from the variables above, with `Options FollowSymLinks` and `AllowOverride All`,
  so Drupal's `.htaccess` works.
- `DirectoryIndex index.html index.php`.
- `.php` files that exist go to `proxy:fcgi://${APACHE_FCGI_HOST_PORT}` with
  `connectiontimeout=5 timeout=600`. A `.php` path that does not exist stays with Apache, so it
  gets a 404 or the app's `.htaccess` front controller. With no PHP-FPM listening, `.php`
  requests get a 503.
- `SSLOptions +StdEnvVars` for `.php` on `:443`, so PHP sees `HTTPS=on`.

The modules docksal/apache adds to the official image's defaults are loaded: `deflate`, `proxy`,
`proxy_http`, `proxy_fcgi`, `proxy_connect`, `ssl`, `socache_shmcb` and `rewrite`. `headers`,
`alias`, `env` and `setenvif` come with the official image.

### Project Apache settings

Point `APACHE_OVERRIDES_DIR` at a directory, usually inside the project checkout (for example
`/var/www/ci/etc/apache`). Apache includes these files from that directory, and skips either one
when it is missing:

- **`httpd-vhost-overrides.conf`**: included last inside both the `:80` and `:443` vhosts, so its
  directives win. For example `RewriteRule`, `ProxyPass`, `Header` or
  `AddOutputFilterByType DEFLATE ...`.
- **`httpd-vhosts.conf`**: included at server level, for extra `<VirtualHost>` blocks or
  `RewriteMap`.

Both can use `${APACHE_DOCUMENTROOT}` and `${APACHE_FCGI_HOST_PORT}`. The files are read where
they are, not copied, so `apachectl -k graceful` picks up edits. When the directory does not
exist, a notice is logged and Apache starts without overrides.

### Basic auth

With both `APACHE_BASIC_AUTH_USER` and `APACHE_BASIC_AUTH_PASS` set, `httpd-foreground` writes
`/usr/local/apache2/htpasswd` (bcrypt) and the docroot requires a valid login on both ports. The
password reaches `htpasswd` on stdin and is never logged. `ProxyPass` routes and extra vhosts
from the overrides are outside the docroot, so they are not covered.

### Logs and signals

The access log goes to stdout and the error log to stderr. The official image's `STOPSIGNAL`
(`SIGWINCH`) makes Apache stop gracefully, finishing requests in flight. `httpd-foreground`
removes a stale pid file before it starts Apache.

## Details worth knowing

- **Running httpd by hand.** `httpd-foreground` writes `conf/devcloud-runtime.conf` and the
  certificate, which `httpd.conf` includes. Arguments after it go to `httpd`, so
  `httpd-foreground -t` checks the config with the container's environment. In a running
  container plain `httpd -t`, `httpd -M` and `apachectl -k graceful` also work, because the
  settings are in that file rather than in the environment.
- **Tools.** `curl` and `openssl` are installed, for health checks and debugging from
  `kubectl exec`. `htpasswd` and the other Apache tools are in `/usr/local/apache2/bin`.
- **Debian updates.** The build runs `apt-get upgrade`, so the weekly no-cache rebuild applies
  Debian security fixes even before the official image is rebuilt.

## Differences from docksal/apache

- Debian trixie rather than Alpine.
- `DOCROOT` is honored. docksal/apache's image set `APACHE_DOCUMENTROOT=/var/www/docroot`, so
  pods always got `/var/www/docroot`.
- The FastCGI default is `127.0.0.1:9000` (same pod), not `cli:9000`.
- Overrides come from `APACHE_OVERRIDES_DIR`, read in place, instead of being copied from
  `/var/www/.docksal/etc/apache` at start.
- The basic auth password is not logged, and `htpasswd` stores it with bcrypt.
- The self-signed certificate is made per container at start (EC P-256, `CN=localhost`), not at
  build time (RSA 4096, empty subject).
- `curl` and `openssl` are installed. There is no Docker `HEALTHCHECK`; Kubernetes probes are set
  in the pod spec.

## Tests

- `tests/structure-test.yaml`: metadata, the config syntax check (with and without `DOCROOT` and
  overrides), the loaded modules, the worker user, logging to stdout/stderr, the tools, and that
  no private key ships in the image.
- `tests/compat-test.sh`: starts real containers and checks the runtime contract end to end:
  docroot selection, HTTPS and its TLS versions, the FastCGI hand-off (404 for a missing `.php`,
  503 with no backend), overrides inside both vhosts and at server level, a graceful restart
  re-reading them, basic auth, and that the password is not logged. With
  `FCGI_BACKEND_IMAGE=ghcr.io/phase2/php-devcloud:8.4` it also starts PHP-FPM in the container's
  network namespace and serves `.php`, `index.php` and `HTTPS` through it.
