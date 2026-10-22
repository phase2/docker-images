#!/usr/bin/env bash
# Test one built image: its container-structure-test specs and, for php-devcloud, the
# compatibility smoke test.
# Usage: scripts/test-image.sh <ci-tools|php-ci|php-devcloud> <image-ref>
# Env:   CST=<path to container-structure-test> (default: on PATH)
#        PLATFORM=<os/arch> of the image when it differs from the host (e.g. linux/amd64)
set -euo pipefail

name="${1:?usage: test-image.sh <ci-tools|php-ci|php-devcloud> <image-ref>}"
ref="${2:?usage: test-image.sh <ci-tools|php-ci|php-devcloud> <image-ref>}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

configs=(images/base/tests/structure-test.yaml)
case "${name}" in
  ci-tools)     configs+=(images/ci-tools/tests/structure-test.yaml) ;;
  php-ci)       configs+=(images/ci-tools/tests/structure-test.yaml images/_shared/structure-test.php.yaml) ;;
  php-devcloud) configs+=(images/_shared/structure-test.php.yaml images/php-devcloud/tests/structure-test.yaml) ;;
  *) echo "unknown image ${name}" >&2; exit 2 ;;
esac

args=()
[[ -n "${PLATFORM:-}" ]] && args+=(--platform "${PLATFORM}")
for c in "${configs[@]}"; do args+=(--config "${c}"); done
"${CST:-container-structure-test}" test --driver docker --image "${ref}" "${args[@]}"

if [[ "${name}" == php-devcloud ]]; then
  images/php-devcloud/tests/compat-test.sh "${ref}"
fi
