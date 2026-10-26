#!/usr/bin/env bash
# Test one built image: its container-structure-test specs and, for php-devcloud and
# httpd-devcloud, the compatibility smoke test.
# Usage: scripts/test-image.sh <ci-tools|php-ci|php-devcloud|httpd-devcloud> <image-ref>
# Env:   CST=<path to container-structure-test> (default: on PATH)
#        PLATFORM=<os/arch> of the image when it differs from the host (e.g. linux/amd64)
#        FCGI_BACKEND_IMAGE=<php-devcloud image>: httpd-devcloud's compat test also serves PHP
#        through it
set -euo pipefail

usage="usage: test-image.sh <ci-tools|php-ci|php-devcloud|httpd-devcloud> <image-ref>"
name="${1:?${usage}}"
ref="${2:?${usage}}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Every image but httpd-devcloud is built FROM base.
base=images/base/tests/structure-test.yaml
case "${name}" in
  ci-tools)       configs=("${base}" images/ci-tools/tests/structure-test.yaml) ;;
  php-ci)         configs=("${base}" images/ci-tools/tests/structure-test.yaml images/_shared/structure-test.php.yaml) ;;
  php-devcloud)   configs=("${base}" images/_shared/structure-test.php.yaml images/php-devcloud/tests/structure-test.yaml) ;;
  httpd-devcloud) configs=(images/httpd-devcloud/tests/structure-test.yaml) ;;
  *) echo "unknown image ${name}" >&2; exit 2 ;;
esac

args=()
[[ -n "${PLATFORM:-}" ]] && args+=(--platform "${PLATFORM}")
for c in "${configs[@]}"; do args+=(--config "${c}"); done
"${CST:-container-structure-test}" test --driver docker --image "${ref}" "${args[@]}"

case "${name}" in
  php-devcloud | httpd-devcloud) "images/${name}/tests/compat-test.sh" "${ref}" ;;
esac
