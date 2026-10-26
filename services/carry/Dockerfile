# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the carry service (Elixir 1.20 on
#                  Erlang/OTP 28, gRPC server on Cowboy, Mnesia, brod).
#                  Stages: toolchain, lint, test, doc-coverage, api-docs,
#                  build and the minimal non-root runtime image used by
#                  Compose.
# Related Docs:    services/carry/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0020, ADR-0032
#
# Stage contract (used by services/carry/Makefile and the root Makefile):
#   toolchain — the official Elixir image on Alpine 3.24 with the C
#               compiler and CMake (the crc32cer NIF of brod is built from
#               source), Hex 2.6.0, the generated gRPC code of
#               contracts/gen/elixir (named build context `contracts`), and
#               the Hex packages locked by mix.lock, compiled for the test,
#               dev and prod environments.
#   lint      — mix format --check-formatted, Credo in strict mode, and a
#               compilation with warnings as errors in every environment.
#   test      — the ExUnit tests (doctests included) against a real Mnesia
#               database, then the schema check of every event the tests
#               published (scripts/validate-events.py, named build context
#               `scripts`).
#   doc-coverage — tools/doc_coverage.exs (every definition, private ones
#               included) and Doctor (100% docs and specs of public
#               definitions).
#   api-docs  — the ExDoc HTML with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — the release `carry` (with its own ERTS) in /out.
#   runtime   — Alpine 3.24 with the shared libraries of the BEAM and of
#               OpenSSL's libcrypto (the :crypto application), the release,
#               the migrations and busybox wget (part of Alpine), user
#               10001, ports 8080 (HTTP) and 9090 (gRPC).

FROM elixir:1.20.4-otp-28-alpine AS toolchain
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# mix local.rebar installs the rebar3 version pinned by this Elixir release.
RUN apk add --no-cache build-base=0.5-r4 cmake=4.2.3-r0 \
    && mix local.hex 2.6.0 --force \
    && mix local.rebar --force
WORKDIR /src
# Dependencies first: the layers are reused while mix.lock is unchanged.
COPY mix.exs mix.lock ./
COPY config/ config/
RUN mix deps.get \
    && for env in test dev prod; do MIX_ENV="$env" mix deps.compile; done
# `contracts` is a named build context (--build-context in the Makefile,
# additional_contexts in Compose), not a stage, which hadolint cannot know.
# hadolint ignore=DL3022
COPY --from=contracts gen/elixir/aaas/carry/ gen/aaas/carry/
COPY . .

FROM toolchain AS lint
RUN mix format --check-formatted \
    && MIX_ENV="test" mix credo --strict --all \
    && for env in test dev prod; do MIX_ENV="$env" mix compile --warnings-as-errors; done

FROM toolchain AS test
# The versions of the documentation image (as in the successor test stage).
RUN apk add --no-cache python3=3.14.8-r0 \
    && python3 -m venv /venv \
    && /venv/bin/pip install --no-cache-dir "jsonschema==4.26.0" "jsonschema-specifications==2025.9.1" \
       "referencing==0.37.0" "rpds-py==2026.9.1" "rfc3339-validator==0.1.4" "six==1.17.0" "attrs==25.4.0"
# `contracts` and `scripts` are named build contexts, not stages.
# hadolint ignore=DL3022
COPY --from=contracts events/ /repo/contracts/events/
# hadolint ignore=DL3022
COPY --from=scripts validate-events.py /repo/scripts/
ENV PRODUCED_DIR=/tmp/produced
RUN MIX_ENV="test" mix test --no-start --warnings-as-errors \
    && /venv/bin/python /repo/scripts/validate-events.py --events /tmp/produced/*.json

FROM toolchain AS doc-coverage
RUN elixir tools/doc_coverage.exs mix.exs src/carry/*.ex src/carry/grpc/*.ex tests/support/*.ex tools/*.exs \
    && mix doctor

FROM toolchain AS api-docs-build
RUN mix docs --formatter html --output /api-docs \
    && test -f /api-docs/index.html

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
RUN MIX_ENV=prod mix release carry --path /out \
    && mkdir -p /out-data/mnesia

FROM alpine:3.24.3 AS runtime

LABEL org.opencontainers.image.title="carry" \
      org.opencontainers.image.description="AaaS carry service (Elixir): Propagates a carry to higher digit positions." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

# The shared libraries of beam.smp (ncurses for the shell's terminal
# support, libstdc++ and libgcc for the JIT) and libcrypto of the :crypto
# application; busybox wget (part of Alpine) answers the Compose
# healthcheck.
RUN apk add --no-cache libncursesw=6.6_p20260516-r0 libstdc++=15.2.0-r5 libgcc=15.2.0-r5 \
       libcrypto3=3.5.9-r0 \
    && adduser -D -H -u 10001 -s /sbin/nologin carry

COPY --from=build /out /app
COPY --from=build --chown=10001:10001 /out-data /data
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the Mnesia volume) belongs to it.
USER 10001:10001
WORKDIR /app

EXPOSE 8080 9090
# RELEASE_DISTRIBUTION=none: the node is nonode@nohost, the name the Mnesia
# schema is bound to (a distributed name would contain the container's
# host name, which changes with every container).
# RELEASE_MODE=interactive: modules are loaded when first used; the default
# (embedded) loads every module of every dependency at boot, 35 MB of code
# instead of 12 MB (measured: 98 MiB against 37 MiB at rest).
# +S 1:1 and +SDcpu 1:1: one scheduler for a container of 0.5 CPU instead of
# one per host core. Measured with 8 concurrent callers: p90 10 ms with one
# scheduler, 66 ms with two, 9 ms with eight, at a peak of 50, 55 and 61 MiB.
# +sbwt none (and its dirty variants): schedulers do not busy-wait for work.
# +P 8192 and +Q 2048: the process and port tables sized for 256 HTTP and
# 256 gRPC connections with margin instead of the defaults of about one
# million processes and 65 536 ports.
ENV AAAS_SERVICE=carry \
    AAAS_HTTP_PORT=8080 \
    AAAS_GRPC_PORT=9090 \
    AAAS_DB_DIR=/data/mnesia \
    AAAS_MIGRATIONS_DIR=/app/migrations \
    RELEASE_DISTRIBUTION=none \
    RELEASE_MODE=interactive \
    ERL_CRASH_DUMP_SECONDS=0 \
    ELIXIR_ERL_OPTIONS="+S 1:1 +SDcpu 1:1 +sbwt none +sbwtdcpu none +sbwtdio none +P 8192 +Q 2048"

ENTRYPOINT ["/app/bin/carry", "start"]
