#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/proto.sh
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Checks and generates the gRPC contracts of contracts/proto
#                  with buf in containers: format and lint, breaking changes
#                  against a git revision, code generation into
#                  contracts/gen/, and the check that the committed
#                  generated code is current. Called by the proto targets of
#                  the Makefile and by CI.
# Related Docs:    ADR-0020, contracts/proto/README.md, contracts/gen/README.md,
#                  infra/buf/Dockerfile, CLAUDE.md (sections 4.3, 6.4)
#
# Usage:
#   scripts/proto.sh lint             buf format (check) and buf lint
#   scripts/proto.sh breaking         buf breaking against PROTO_AGAINST
#   scripts/proto.sh generate         regenerate contracts/gen/
#   scripts/proto.sh check-generated  fail if contracts/gen/ is not what
#                                     `generate` would produce
#
# lint and breaking run in the official buf image (small, no plugins);
# generate and check-generated run in aaas/buf:dev (buf plus the protoc
# plugins of nine languages), which is built from infra/buf/ when missing.
#
# Environment:
#   PROTO_AGAINST   git revision that `breaking` compares with. Default: the
#                   merge base of HEAD and main, or HEAD~1 when HEAD is on
#                   main. When the revision has no contracts/proto/buf.yaml
#                   (before the contracts existed), the check is skipped.
#   BUF_LINT_IMAGE  image of lint and breaking (default bufbuild/buf:1.74.0)
#   BUF_IMAGE       image of generate and check-generated
#                   (default aaas/buf:dev)
#
# Exit status: 0 on success; 2 on usage errors; otherwise the status of the
# failing command (buf exits with 100 when lint or breaking finds problems,
# check-generated exits with 1 when contracts/gen/ is out of date).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUF_LINT_IMAGE="${BUF_LINT_IMAGE:-bufbuild/buf:1.74.0}"
BUF_IMAGE="${BUF_IMAGE:-aaas/buf:dev}"
PROTO_DIR="contracts/proto"
GEN_DIR="contracts/gen"
# Scratch directory (git-ignored) for the baseline of `breaking`.
AGAINST_DIR="build/proto-against"

# die <message>: print an error to stderr and exit with status 2.
die() {
  echo "error: $*" >&2
  exit 2
}

# run_buf <image> <args...>: run buf with <args> in <image> with the
# repository mounted at /work, as the caller's UID so that written files are
# theirs.
run_buf() {
  local image="$1"
  shift
  docker run --rm --user "$(id -u):$(id -g)" --env BUF_CACHE_DIR=/tmp/buf-cache \
    --volume "${ROOT}:/work" --workdir /work "$image" "$@"
}

# run_sh <image> <script>: like run_buf, but run a sh script instead of buf.
run_sh() {
  local image="$1"
  shift
  docker run --rm --user "$(id -u):$(id -g)" --env BUF_CACHE_DIR=/tmp/buf-cache \
    --volume "${ROOT}:/work" --workdir /work --entrypoint sh "$image" -c "$1"
}

# ensure_buf_image: build aaas/buf:dev from infra/buf/ if it does not exist.
ensure_buf_image() {
  if ! docker image inspect "$BUF_IMAGE" >/dev/null 2>&1; then
    echo "==> building ${BUF_IMAGE} (first time: compiles the plugins, takes a while)"
    docker build --tag "$BUF_IMAGE" "${ROOT}/infra/buf"
  fi
}

# default_against: print the default baseline revision of `breaking`.
default_against() {
  local main head base
  if git -C "$ROOT" rev-parse --verify --quiet origin/main >/dev/null; then
    main="origin/main"
  else
    main="main"
  fi
  head="$(git -C "$ROOT" rev-parse HEAD)"
  base="$(git -C "$ROOT" merge-base "$main" HEAD)"
  if [ "$base" = "$head" ]; then
    git -C "$ROOT" rev-parse HEAD~1
  else
    echo "$base"
  fi
}

# cmd_lint: check formatting (buf format) and lint rules (buf.yaml).
cmd_lint() {
  echo "==> buf format (check) ${PROTO_DIR}"
  run_buf "$BUF_LINT_IMAGE" format --diff --exit-code "$PROTO_DIR"
  echo "==> buf lint ${PROTO_DIR}"
  run_buf "$BUF_LINT_IMAGE" lint "$PROTO_DIR"
}

# cmd_breaking: compare contracts/proto with the same directory at
# PROTO_AGAINST, extracted with git archive (no git needed in the image).
cmd_breaking() {
  local against="${PROTO_AGAINST:-}"
  if [ -z "$against" ]; then
    against="$(default_against)"
  fi
  if ! git -C "$ROOT" cat-file -e "${against}:${PROTO_DIR}/buf.yaml" 2>/dev/null; then
    echo "==> buf breaking: ${against} has no ${PROTO_DIR}/buf.yaml; nothing to compare with, skipped."
    return 0
  fi
  rm -rf "${ROOT:?}/${AGAINST_DIR}"
  mkdir -p "${ROOT}/${AGAINST_DIR}"
  git -C "$ROOT" archive "$against" "$PROTO_DIR" | tar -x -C "${ROOT}/${AGAINST_DIR}"
  echo "==> buf breaking ${PROTO_DIR} against ${against}"
  run_buf "$BUF_LINT_IMAGE" breaking "$PROTO_DIR" --against "${AGAINST_DIR}/${PROTO_DIR}"
}

# cmd_generate: regenerate contracts/gen/ from contracts/proto/buf.gen.yaml.
cmd_generate() {
  ensure_buf_image
  echo "==> buf generate ${PROTO_DIR} -> ${GEN_DIR}"
  run_sh "$BUF_IMAGE" "cd ${PROTO_DIR} && buf generate"
}

# cmd_check_generated: generate into a scratch copy inside the container and
# compare it with the committed contracts/gen/.
cmd_check_generated() {
  ensure_buf_image
  echo "==> generated code in ${GEN_DIR} is current"
  run_sh "$BUF_IMAGE" "
    set -e
    mkdir -p /tmp/check/contracts
    cp -R ${PROTO_DIR} /tmp/check/contracts/proto
    cd /tmp/check/contracts/proto
    buf generate
    if ! diff -r -x README.md /tmp/check/contracts/gen /work/${GEN_DIR}; then
      echo 'error: ${GEN_DIR} is out of date; run: make proto' >&2
      exit 1
    fi
    echo '    up to date'
  "
}

[ $# -eq 1 ] || die "usage: scripts/proto.sh lint|breaking|generate|check-generated"
case "$1" in
  lint) cmd_lint ;;
  breaking) cmd_breaking ;;
  generate) cmd_generate ;;
  check-generated) cmd_check_generated ;;
  *) die "unknown command: $1 (expected lint, breaking, generate or check-generated)" ;;
esac
