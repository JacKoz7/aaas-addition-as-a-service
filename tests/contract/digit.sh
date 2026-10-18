#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          tests/contract/digit.sh
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Shared contract test of the digit services: runs
#                  tests/contract/digit_contract.py against one running
#                  digit service, in a container on its Compose network.
#                  Called by `make contract-digit-<d>` and by the steps that
#                  build the digit services (P2.3-P2.12).
# Related Docs:    tests/contract/README.md, contracts/http/digit.yaml,
#                  ADR-0021, CLAUDE.md 4.4
#
# Usage:
#   tests/contract/digit.sh <digit 0-9> [base-url]
#
#   base-url defaults to http://digit-<digit>:8080, the service's address on
#   the network aaas-services. The test runs in the documentation tool image
#   (Python with PyYAML and jsonschema), with the repository mounted
#   read-only, so nothing is needed on the host besides Docker.
#
# Environment:
#   AAAS_CONTRACT_NETWORK   Docker network to join (default aaas-services)
#
# Exit status: 0 when every check passed, 1 when a check failed, 2 on usage
# errors or when the network does not exist.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NETWORK="${AAAS_CONTRACT_NETWORK:-aaas-services}"
IMAGE="aaas/docs-portal:dev"

if [ $# -lt 1 ] || [ $# -gt 2 ] || ! [[ "$1" =~ ^[0-9]$ ]]; then
  echo "usage: tests/contract/digit.sh <digit 0-9> [base-url]" >&2
  exit 2
fi
digit="$1"
url="${2:-http://digit-${digit}:8080}"

if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  echo "error: Docker network ${NETWORK} does not exist; start the system with: make up" >&2
  exit 2
fi
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build --quiet --tag "$IMAGE" "${ROOT}/infra/docs-portal" >/dev/null
fi

echo "==> digit contract test: digit-${digit} at ${url} (network ${NETWORK})"
docker run --rm --network "$NETWORK" --user "$(id -u):$(id -g)" \
  --volume "${ROOT}:/repo:ro" --workdir /repo --entrypoint python3 "$IMAGE" \
  tests/contract/digit_contract.py "$digit" "$url"
