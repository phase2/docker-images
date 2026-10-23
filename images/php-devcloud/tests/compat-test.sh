#!/usr/bin/env bash
# Compatibility smoke test for php-devcloud: exercises the runtime contract devcloud pods and
# their tooling rely on (README.md "php-devcloud at runtime").
# Usage: images/php-devcloud/tests/compat-test.sh <image>
# Single-quoted $vars below are expanded inside the container, not here.
# shellcheck disable=SC2016
set -euo pipefail

image="${1:?usage: compat-test.sh <image>}"
tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# A project checkout as the pod sees it: probe script plus a PHP overrides directory.
overrides=/var/www/.overrides/php
mkdir -p "${work}/www/.overrides/php"
cat > "${work}/www/probe.php" <<'PHP'
<?php
echo json_encode([
  'user' => posix_getpwuid(posix_geteuid())['name'],
  'mysql_host' => getenv('MYSQL_HOST'),
  'memory_limit' => ini_get('memory_limit'),
  'max_input_vars' => ini_get('max_input_vars'),
  'assertions' => ini_get('zend.assertions'),
]);
PHP
printf 'max_input_vars = 4321\n' > "${work}/www/.overrides/php/project.ini"
printf 'php_admin_value[memory_limit] = 1536M\n' > "${work}/www/.overrides/php/php-fpm.conf"

start() { # name www-dir-or-"" [docker create args...]; www-dir is copied into /var/www first
  local name="$1" www="$2"; shift 2
  "${docker[@]}" create --name "${name}" "$@" "${image}" >/dev/null
  containers+=("${name}")
  "${docker[@]}" cp "${tests_dir}/fcgi.php" "${name}:/usr/local/lib/fcgi.php"
  if [[ -n "${www}" ]]; then "${docker[@]}" cp "${www}/." "${name}:/var/www/"; fi
  "${docker[@]}" start "${name}" >/dev/null
}

wait_for_fpm() {
  local name="$1"
  for _ in $(seq 1 30); do
    if "${docker[@]}" exec "${name}" php /usr/local/lib/fcgi.php "" /ping >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  "${docker[@]}" logs "${name}" >&2 || true
  return 1
}

plain="php-devcloud-compat-plain-$$"
php_field() { # field json; decoded with the image's own PHP so the host needs no jq
  "${docker[@]}" exec "${plain}" php -r 'echo json_decode($argv[1], true)[$argv[2]] ?? "";' -- "$2" "$1"
}

echo "== default container (no overrides)"
start "${plain}" "" -e MYSQL_HOST=db.example.internal
if wait_for_fpm "${plain}"; then pass "php-fpm answers /ping on :9000"; else fail "php-fpm did not answer /ping"; fi
expect "image default user is root" "root" "$("${docker[@]}" exec "${plain}" id -un)"
expect "runuser -u docker works as root" "docker" "$("${docker[@]}" exec "${plain}" runuser -u docker -- id -un)"
expect "runuser keeps HOME=/home/docker" "/home/docker" "$("${docker[@]}" exec "${plain}" runuser -u docker -- bash -c 'echo "${HOME}"')"
if "${docker[@]}" exec -u 1000 "${plain}" sudo -n chown -R docker:docker /var/www; then
  pass "sudo chown as uid 1000"
else
  fail "sudo chown as uid 1000"
fi
expect "sudo su works as uid 1000" "root" "$("${docker[@]}" exec -u 1000 "${plain}" sudo -n su -c 'id -un')"
expect "HOME writable for docker" "yes" "$("${docker[@]}" exec -u 1000 "${plain}" bash -c 'touch "${HOME}/.probe" && echo yes')"
expect "vendor/bin on PATH" "yes" "$("${docker[@]}" exec -u 1000 "${plain}" bash -c '[[ ":${PATH}:" == *":/var/www/vendor/bin:"* ]] && echo yes')"
expect "login shell keeps vendor/bin and Node on PATH" "yes" "$("${docker[@]}" exec "${plain}" runuser -u docker -- bash -lc '[[ ":${PATH}:" == *":/var/www/vendor/bin:"* ]] && command -v node >/dev/null && echo yes')"
expect "root git works in docker-owned /var/www" "yes" "$("${docker[@]}" exec "${plain}" bash -c 'git init -q /var/www && git init -q /var/www/sub && chown -R docker:docker /var/www && git -C /var/www status >/dev/null && git -C /var/www/sub status >/dev/null && echo yes; rm -rf /var/www/.git /var/www/sub')"
expect "unset PHP_OVERRIDES_DIR is logged" "1" "$("${docker[@]}" logs "${plain}" 2>&1 | grep -c 'PHP_OVERRIDES_DIR is not set' || true)"
expect "CLI memory_limit" "-1" "$("${docker[@]}" exec "${plain}" php -r 'echo ini_get("memory_limit");')"
expect "CLI runs assertions" "1" "$("${docker[@]}" exec "${plain}" php -r 'echo ini_get("zend.assertions");')"
setuid="$("${docker[@]}" exec "${plain}" find / -xdev -perm /6000 -type f)"
expect "only sudo is setuid" "/usr/bin/sudo" "${setuid}"

"${docker[@]}" cp "${work}/www/probe.php" "${plain}:/var/www/probe.php"
body="$("${docker[@]}" exec "${plain}" php /usr/local/lib/fcgi.php /var/www/probe.php || true)"
expect "FPM worker runs as docker" "docker" "$(php_field user "${body}")"
expect "pod env reaches FPM workers (clear_env = no)" "db.example.internal" "$(php_field mysql_host "${body}")"
expect "FPM memory_limit default" "1024M" "$(php_field memory_limit "${body}")"
expect "FPM runs assertions" "1" "$(php_field assertions "${body}")"

echo "== nvm (.nvmrc)"
node_out="$("${docker[@]}" exec "${plain}" runuser -u docker -- bash -c '
  set -e; mkdir -p /tmp/nvmrc && cd /tmp/nvmrc && echo 20 > .nvmrc
  . "${NVM_DIR}/nvm.sh"; nvm install >/dev/null 2>&1; nvm use >/dev/null
  echo "$(node -v | cut -d. -f1) yarn-$(yarn -v | cut -d. -f1)"' 2>&1 || true)"
expect ".nvmrc 20 installs Node 20 with yarn 1" "v20 yarn-1" "${node_out}"

echo "== project overrides from PHP_OVERRIDES_DIR"
over="php-devcloud-compat-over-$$"
start "${over}" "${work}/www" -e PHP_OVERRIDES_DIR="${overrides}"
if wait_for_fpm "${over}"; then pass "php-fpm starts with project overrides"; else fail "php-fpm failed with project overrides"; fi
body="$("${docker[@]}" exec "${over}" php /usr/local/lib/fcgi.php /var/www/probe.php || true)"
expect "php-fpm.conf override (FPM memory_limit)" "1536M" "$(php_field memory_limit "${body}")"
expect "*.ini override reaches FPM" "4321" "$(php_field max_input_vars "${body}")"
expect "*.ini override reaches CLI" "4321" "$("${docker[@]}" exec "${over}" php -r 'echo ini_get("max_input_vars");')"
expect "*.ini override survives sudo" "4321" "$("${docker[@]}" exec -u 1000 "${over}" sudo php -r 'echo ini_get("max_input_vars");')"
expect "*.ini override survives sudo su" "4321" "$("${docker[@]}" exec -u 1000 "${over}" sudo su -c 'php -r "echo ini_get(\"max_input_vars\");"')"

echo "== xdebug toggle"
expect "xdebug off by default" "off" "$("${docker[@]}" exec "${plain}" php -r 'echo extension_loaded("xdebug") ? "on" : "off";')"
expect "XDEBUG_ENABLED=1 turns it on" "on" "$("${docker[@]}" run --rm -e XDEBUG_ENABLED=1 "${image}" php -r 'echo extension_loaded("xdebug") ? "on" : "off";')"

if (( failures > 0 )); then
  echo "${failures} check(s) failed" >&2
  exit 1
fi
echo "compat test passed"
