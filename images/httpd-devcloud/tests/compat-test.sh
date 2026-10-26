#!/usr/bin/env bash
# Compatibility smoke test for httpd-devcloud: exercises the runtime contract devcloud pods rely
# on (images/httpd-devcloud/README.md): docroot selection, project overrides, basic auth, HTTPS
# and the FastCGI hand-off to PHP-FPM.
# Usage: images/httpd-devcloud/tests/compat-test.sh <image>
# Env:   FCGI_BACKEND_IMAGE=<php-devcloud image> also runs .php requests through a real PHP-FPM
#        sharing the container's network, as in a pod. Without it, .php requests must get a 503.
# Single-quoted $vars below are expanded inside the container (or by PHP), not here.
# shellcheck disable=SC2016
set -euo pipefail

image="${1:?usage: compat-test.sh <image>}"
docker_cmd="${DOCKER:-docker}"
read -r -a docker <<<"${docker_cmd}"
work="$(mktemp -d)"
containers=()

cleanup() {
  for c in "${containers[@]}"; do "${docker[@]}" rm -f "${c}" >/dev/null 2>&1 || true; done
  rm -rf "${work}"
}
trap cleanup EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }
expect() { # name expected actual
  if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1: expected '$2', got '$3'"; fi
}

# A project checkout as the pod sees it at /var/www: two candidate docroots, a PHP probe, and
# project overrides in ci/etc/apache.
www="${work}/www"
overrides=/var/www/ci/etc/apache
mkdir -p "${www}/docroot" "${www}/web" "${www}/extra" "${www}/ci/etc/apache"
echo docroot > "${www}/docroot/index.html"
echo web > "${www}/web/index.html"
echo extra-vhost > "${www}/extra/index.html"
printf '<?php echo "php:", php_sapi_name(), ":", $_SERVER["SCRIPT_FILENAME"];\n' > "${www}/web/probe.php"
cat > "${www}/ci/etc/apache/httpd-vhost-overrides.conf" <<'CONF'
RewriteEngine On
RewriteRule ^/rewritten$ /index.html [PT]
Header always set X-Project-Override yes
CONF
cat > "${www}/ci/etc/apache/httpd-vhosts.conf" <<'CONF'
<VirtualHost *:80>
	ServerName extra.test
	DocumentRoot /var/www/extra
	<Directory /var/www/extra>
		Require all granted
	</Directory>
</VirtualHost>
CONF
# The checkout belongs to uid 1000 in the pod; Apache's workers (www-data) only read it.
chmod -R a+rX "${www}"

start() { # name [docker create args...]; the checkout is copied to /var/www first
  local name="$1"; shift
  "${docker[@]}" create --name "${name}" "$@" "${image}" >/dev/null
  containers+=("${name}")
  "${docker[@]}" cp "${www}/." "${name}:/var/www/"
  "${docker[@]}" start "${name}" >/dev/null
  for _ in $(seq 1 30); do
    if "${docker[@]}" exec "${name}" curl -s -o /dev/null http://localhost/ 2>/dev/null; then return 0; fi
    sleep 1
  done
  "${docker[@]}" logs "${name}" >&2 || true
  fail "${name}: Apache did not answer on :80"
  return 1
}

get() { # name url [curl args...]: the response body, from inside the container
  local name="$1" url="$2"; shift 2
  "${docker[@]}" exec "${name}" curl -sk "$@" "${url}" || true
}
status() { # name url [curl args...]: the HTTP status code
  local name="$1" url="$2"; shift 2
  "${docker[@]}" exec "${name}" curl -sk -o /dev/null -w '%{http_code}' "$@" "${url}" || true
}

echo "== defaults (no DOCROOT, no overrides)"
plain="httpd-devcloud-compat-plain-$$"
start "${plain}"
expect "default DocumentRoot is /var/www/docroot" "docroot" "$(get "${plain}" http://localhost/)"
expect "unset APACHE_OVERRIDES_DIR is logged once" "1" "$("${docker[@]}" logs "${plain}" 2>&1 | grep -c 'APACHE_OVERRIDES_DIR is not set' || true)"
expect "no override header without APACHE_OVERRIDES_DIR" "" "$(get "${plain}" http://localhost/ -o /dev/null -D - | grep -i '^x-project-override' || true)"
expect "Apache runs as PID 1" "httpd" "$("${docker[@]}" exec "${plain}" cat /proc/1/comm)"
expect "workers run as www-data" "www-data" "$("${docker[@]}" exec "${plain}" bash -c '
  for d in /proc/[0-9]*; do read -r _ _ _ ppid _ < "${d}/stat" && [[ "${ppid}" == 1 ]] && stat -c %U "${d}"; done | sort -u' 2>/dev/null)"
expect "access log goes to stdout" "yes" "$("${docker[@]}" logs "${plain}" 2>/dev/null | grep -q '"GET / HTTP/1.1" 200' && echo yes)"
expect "ServerName is set (no AH00558 warning)" "0" "$("${docker[@]}" logs "${plain}" 2>&1 | grep -c AH00558 || true)"

echo "== HTTPS on :443"
expect "https://localhost answers" "docroot" "$(get "${plain}" https://localhost/)"
expect "TLS 1.2 accepted" "200" "$(status "${plain}" https://localhost/ --tlsv1.2 --tls-max 1.2)"
expect "TLS 1.3 accepted" "200" "$(status "${plain}" https://localhost/ --tlsv1.3)"
expect "TLS 1.1 refused" "000" "$(status "${plain}" https://localhost/ --tlsv1.1 --tls-max 1.1 --ciphers DEFAULT@SECLEVEL=0)"
expect "certificate is per container (no key in the image)" "yes" "$("${docker[@]}" exec "${plain}" bash -c 'test -s /usr/local/apache2/conf/server.key && echo yes')"

echo "== FastCGI hand-off"
expect "missing .php stays with Apache (404)" "404" "$(status "${plain}" http://localhost/missing.php)"
"${docker[@]}" exec "${plain}" bash -c 'echo "<?php" > /var/www/docroot/exists.php'
expect "existing .php goes to FastCGI (503 with no backend)" "503" "$(status "${plain}" http://localhost/exists.php)"
expect "the proxy error names the default backend 127.0.0.1:9000" "yes" "$("${docker[@]}" logs "${plain}" 2>&1 | grep -q 'AH00957.*127\.0\.0\.1:9000' && echo yes)"

echo "== DOCROOT and APACHE_DOCUMENTROOT"
abs="httpd-devcloud-compat-abs-$$"
start "${abs}" -e DOCROOT=/var/www/web
expect "absolute DOCROOT is honored" "web" "$(get "${abs}" http://localhost/)"
rel="httpd-devcloud-compat-rel-$$"
start "${rel}" -e DOCROOT=web
expect "relative DOCROOT resolves under /var/www" "web" "$(get "${rel}" http://localhost/)"
both="httpd-devcloud-compat-both-$$"
start "${both}" -e DOCROOT=/var/www/web -e APACHE_DOCUMENTROOT=/var/www/docroot
expect "APACHE_DOCUMENTROOT beats DOCROOT" "docroot" "$(get "${both}" http://localhost/)"

echo "== project overrides and basic auth"
over="httpd-devcloud-compat-over-$$"
pass_secret="s3cret-$$"
start "${over}" -e DOCROOT=/var/www/web -e APACHE_OVERRIDES_DIR="${overrides}" \
  -e APACHE_BASIC_AUTH_USER=preview -e APACHE_BASIC_AUTH_PASS="${pass_secret}"
expect "basic auth: 401 without credentials" "401" "$(status "${over}" http://localhost/)"
expect "basic auth: 401 with a wrong password" "401" "$(status "${over}" http://localhost/ -u preview:wrong)"
expect "basic auth: 200 with credentials" "200" "$(status "${over}" http://localhost/ -u "preview:${pass_secret}")"
expect "basic auth applies on :443 too" "401" "$(status "${over}" https://localhost/)"
expect "password is not logged" "0" "$("${docker[@]}" logs "${over}" 2>&1 | grep -c "${pass_secret}" || true)"
expect "override directive (RewriteRule) on :80" "web" "$(get "${over}" http://localhost/rewritten -u "preview:${pass_secret}")"
expect "override directive (RewriteRule) on :443" "web" "$(get "${over}" https://localhost/rewritten -u "preview:${pass_secret}")"
expect "override directive (Header) on :80" "yes" "$(get "${over}" http://localhost/ -u "preview:${pass_secret}" -o /dev/null -D - | tr -d '\r' | sed -n 's/^x-project-override: //Ip')"
expect "server-level httpd-vhosts.conf adds a vhost" "extra-vhost" "$(get "${over}" http://localhost/ -H 'Host: extra.test')"
expect "no notice when APACHE_OVERRIDES_DIR is set" "0" "$("${docker[@]}" logs "${over}" 2>&1 | grep -c 'APACHE_OVERRIDES_DIR' || true)"
"${docker[@]}" exec "${over}" bash -c "echo 'Header always set X-Project-Override reloaded' > ${overrides}/httpd-vhost-overrides.conf && apachectl -k graceful"
sleep 2
expect "a graceful restart re-reads the overrides in place" "reloaded" "$(get "${over}" http://localhost/ -u "preview:${pass_secret}" -o /dev/null -D - | tr -d '\r' | sed -n 's/^x-project-override: //Ip')"

missing="httpd-devcloud-compat-missing-$$"
start "${missing}" -e APACHE_OVERRIDES_DIR=/var/www/nonexistent
expect "a missing overrides directory is logged, and Apache still starts" "1" "$("${docker[@]}" logs "${missing}" 2>&1 | grep -c 'is not a directory' || true)"

if [[ -n "${FCGI_BACKEND_IMAGE:-}" ]]; then
  echo "== PHP through ${FCGI_BACKEND_IMAGE} (shared network and /var/www, as in a pod)"
  vol="httpd-devcloud-compat-$$"
  "${docker[@]}" volume create "${vol}" >/dev/null
  trap 'cleanup; "${docker[@]}" volume rm -f "${vol}" >/dev/null 2>&1 || true' EXIT
  web="httpd-devcloud-compat-web-$$"
  start "${web}" -v "${vol}:/var/www" -e DOCROOT=/var/www/web
  fpm="httpd-devcloud-compat-fpm-$$"
  "${docker[@]}" run -d --name "${fpm}" --network "container:${web}" -v "${vol}:/var/www" "${FCGI_BACKEND_IMAGE}" >/dev/null
  containers+=("${fpm}")
  body=""
  for _ in $(seq 1 30); do
    body="$(get "${web}" http://localhost/probe.php)"
    [[ "${body}" == php:* ]] && break
    sleep 1
  done
  expect "probe.php runs in PHP-FPM" "php:fpm-fcgi:/var/www/web/probe.php" "${body}"
  "${docker[@]}" exec "${web}" bash -c 'mv /var/www/web/index.html /var/www/web/index.htm && cp /var/www/web/probe.php /var/www/web/index.php'
  expect "DirectoryIndex falls through to index.php" "php:fpm-fcgi:/var/www/web/index.php" "$(get "${web}" http://localhost/)"
  "${docker[@]}" exec "${web}" bash -c 'echo "<?php echo \$_SERVER[\"HTTPS\"] ?? \"off\";" > /var/www/web/https.php'
  expect "PHP over :443 sees HTTPS=on" "on" "$(get "${web}" https://localhost/https.php)"
  expect "PHP over :80 sees no HTTPS" "off" "$(get "${web}" http://localhost/https.php)"
fi

if (( failures > 0 )); then
  echo "${failures} check(s) failed" >&2
  exit 1
fi
echo "compat test passed"
