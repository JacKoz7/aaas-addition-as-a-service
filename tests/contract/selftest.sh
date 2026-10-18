#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          tests/contract/selftest.sh
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Self-test of the digit contract test: runs
#                  tests/contract/digit.sh against test doubles
#                  (tests/contract/stub/digit_stub.py) and requires it to pass
#                  for conforming doubles and to fail for faulty ones.
#                  Called by `make contract-selftest` and by CI.
# Related Docs:    tests/contract/README.md, ADR-0021
#
# Usage:
#   tests/contract/selftest.sh
#
# Starts its own Docker network and containers and removes them on exit;
# no running AaaS system is needed.
#
# Exit status: 0 when every expectation held, 1 otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="aaas/docs-portal:dev"
NETWORK="aaas-contract-selftest"
PREFIX="aaas-contract-stub"

# Cases: <container suffix>|<digit>|<fault>|<expected exit status>.
CASES=(
  "0|0|none|0"
  "4|4|none|0"
  "9|9|none|0"
  "wrong-next|5|wrong-next|1"
  "plain-errors|3|plain-errors|1"
)

# cleanup: remove the doubles and the network.
cleanup() {
  local case name
  for case in "${CASES[@]}"; do
    name="${PREFIX}-${case%%|*}"
    docker rm --force "$name" >/dev/null 2>&1 || true
  done
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# wait_ready <container>: wait up to 10 s until the double answers /health.
wait_ready() {
  local _
  for _ in $(seq 1 50); do
    if docker exec "$1" python3 -c \
      'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=1)' 2>/dev/null; then
      return 0
    fi
    sleep 0.2
  done
  echo "error: $1 did not start" >&2
  return 1
}

docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build --quiet --tag "$IMAGE" "${ROOT}/infra/docs-portal" >/dev/null
cleanup
docker network create "$NETWORK" >/dev/null

for case in "${CASES[@]}"; do
  IFS='|' read -r suffix digit fault _ <<<"$case"
  docker run --detach --name "${PREFIX}-${suffix}" --network "$NETWORK" \
    --env "DIGIT=${digit}" --env "FAULT=${fault}" \
    --volume "${ROOT}/tests/contract/stub:/stub:ro" --entrypoint python3 "$IMAGE" /stub/digit_stub.py >/dev/null
done

failures=0
for case in "${CASES[@]}"; do
  IFS='|' read -r suffix digit fault expected <<<"$case"
  wait_ready "${PREFIX}-${suffix}"
  status=0
  AAAS_CONTRACT_NETWORK="$NETWORK" "${ROOT}/tests/contract/digit.sh" "$digit" "http://${PREFIX}-${suffix}:8080" || status=$?
  if [ "$status" -eq "$expected" ]; then
    echo "==> self-test: digit ${digit}, fault ${fault}: exit ${status} as expected"
  else
    echo "==> self-test FAILED: digit ${digit}, fault ${fault}: exit ${status}, expected ${expected}" >&2
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "error: ${failures} self-test case(s) did not behave as expected" >&2
  exit 1
fi
echo "==> contract test self-test passed (${#CASES[@]} cases)"
