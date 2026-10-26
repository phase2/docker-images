#!/usr/bin/env bash
# Run one Makefile target for several image variants in parallel, each into its own log, then
# print the logs of the variants that failed. Backs `make test-all` and `make scan-all`.
# Usage: scripts/each-variant.sh <make-target> <variant>...   (variant: ci-tools or <image>:<php>)
# Env:   MAKE=<make binary>; anything the target reads (DOCKER, CST, PLATFORM, ...) passes through.
set -euo pipefail

target="${1:?usage: each-variant.sh <make-target> <variant>...}"
shift
cd "$(dirname "${BASH_SOURCE[0]}")/.."
logs="$(mktemp -d)"
trap 'rm -rf "${logs}"' EXIT

pids=()
for v in "$@"; do
  args=(IMAGE="${v%%:*}")
  [[ "${v}" == *:* ]] && args+=(PHP="${v#*:}")
  "${MAKE:-make}" --no-print-directory "${target}" "${args[@]}" >"${logs}/${v/:/-}.log" 2>&1 &
  pids+=("$!")
done

failed=()
for i in "${!pids[@]}"; do
  v="${*:i+1:1}"
  if wait "${pids[i]}"; then
    printf 'ok   %s %s\n' "${target}" "${v}"
  else
    printf 'FAIL %s %s\n' "${target}" "${v}"
    failed+=("${v}")
  fi
done

# ${a[@]+...}: bash 3.2 (macOS) treats an empty array as unset under `set -u`.
for v in ${failed[@]+"${failed[@]}"}; do
  printf '\n===== %s %s =====\n' "${target}" "${v}"
  cat "${logs}/${v/:/-}.log"
done
[[ ${#failed[@]} -eq 0 ]]
