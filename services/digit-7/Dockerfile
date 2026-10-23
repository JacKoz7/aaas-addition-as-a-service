# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-7
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-7 service (Gleam 1.19 on
#                  Erlang/OTP 28, gen_tcp, SQLite through sqlight/esqlite).
#                  Stages: toolchain, lint, test, doc-coverage, api-docs,
#                  build and the minimal non-root runtime image used by
#                  Compose.
# Related Docs:    services/digit-7/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022, ADR-0029
#
# Stage contract (used by services/digit-7/Makefile and the root Makefile):
#   toolchain — Erlang/OTP 28 on Alpine 3.24 with the C compiler (the
#               esqlite NIF is built from source) and the Gleam binary,
#               checked against its release checksum; the Hex packages
#               locked by manifest.toml are fetched and compiled.
#   lint      — gleam format --check and a build with warnings as errors.
#   test      — the gleeunit tests against the real migrations.
#   doc-coverage — dev/doc_coverage.gleam (a doc comment on every
#               definition and constructor, public and private, and a
#               module comment in every module) and gleam docs build.
#   api-docs  — the gleam docs HTML with an index.html at the root,
#               exported by `make api-docs` and published in the portal
#               (ADR-0010).
#   build     — the Erlang shipment (compiled BEAM files of the service and
#               its runtime packages, the esqlite NIF), in /out.
#   runtime   — Alpine 3.24 with the three shared libraries of the BEAM,
#               only the erts, kernel and stdlib parts of Erlang/OTP, the
#               shipment and busybox wget (part of Alpine), user 10001,
#               port 8080 (HTTP only: the digit contract has no gRPC,
#               CLAUDE.md 4.4).

FROM erlang:28.5.0.8-alpine AS toolchain
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
ARG GLEAM_VERSION=1.19.2
# The release checksums of the musl builds of Gleam (GitHub release assets).
RUN apk add --no-cache build-base=0.5-r4 \
    && case "$(uname -m)" in \
         aarch64) sum=d1d1a9d53f6b317c0563a4806873c8ccace54291ead023373728af379402d4f1 ;; \
         x86_64) sum=2ba2afb66ca9f6dcc01a4a6e9169b6942963bad6483bec9571ddc078cfe6f41f ;; \
         *) echo "unsupported architecture $(uname -m)" && exit 1 ;; \
       esac \
    && wget -qO /tmp/gleam.tgz \
         "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-$(uname -m)-unknown-linux-musl.tar.gz" \
    && echo "${sum}  /tmp/gleam.tgz" | sha256sum -c - \
    && tar -xzf /tmp/gleam.tgz -C /usr/local/bin \
    && rm /tmp/gleam.tgz
WORKDIR /src
# Dependencies first: the layer is reused while manifest.toml is unchanged.
COPY gleam.toml manifest.toml ./
RUN gleam deps download
COPY . .
RUN gleam build

FROM toolchain AS lint
RUN gleam format --check src test dev \
    && gleam build --warnings-as-errors \
    && echo "lint: gleam format and the compiler (warnings as errors) clean"

FROM toolchain AS test
RUN gleam test

FROM toolchain AS doc-coverage
RUN gleam run -m doc_coverage \
    && gleam docs build \
    && echo "doc-coverage: 100% (every definition documented; gleam docs built)"

FROM toolchain AS api-docs-build
# gleam docs links its pages relatively, so the export works under the
# portal's api/digit-7/ (ADR-0010); it documents the public definitions.
RUN gleam docs build \
    && cp -R build/dev/docs/digit7 /api-docs

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
# /out/lib: one directory per package (ebin, priv), found through ERL_LIBS;
# /out/otp: the parts of Erlang/OTP the service loads (the boot files, the
# emulator, kernel and stdlib); /out/data: the volume's mount point.
RUN gleam export erlang-shipment \
    && mkdir -p /out/data /out/otp/lib \
    && cp -R build/erlang-shipment /out/lib \
    && rm /out/lib/entrypoint.sh /out/lib/entrypoint.ps1 \
    && cp -R /usr/local/lib/erlang/bin /usr/local/lib/erlang/erts-* /out/otp/ \
    && cp -R /usr/local/lib/erlang/lib/kernel-* /usr/local/lib/erlang/lib/stdlib-* \
         /usr/local/lib/erlang/lib/erts-* /out/otp/lib/ \
    && rm -rf /out/otp/lib/*/src /out/otp/lib/*/include /out/otp/erts-*/include \
         /out/otp/erts-*/src /out/otp/erts-*/doc /out/otp/erts-*/man

FROM alpine:3.24.3 AS runtime

LABEL org.opencontainers.image.title="digit-7" \
      org.opencontainers.image.description="AaaS digit-7 service (Gleam): Authoritative source for the value and successor of digit 7." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

# The shared libraries of beam.smp (ncurses for the shell's terminal
# support, libstdc++ and libgcc for the JIT); busybox wget (part of
# Alpine) answers the Compose healthcheck.
RUN apk add --no-cache libncursesw=6.6_p20260516-r0 libstdc++=15.2.0-r5 libgcc=15.2.0-r5 \
    && adduser -D -H -u 10001 -s /sbin/nologin digit

# The erl script expects Erlang/OTP at the path it was installed to.
COPY --from=build /out/otp /usr/local/lib/erlang
COPY --from=build /out/lib /app/lib
COPY --from=build --chown=10001:10001 /out/data /data
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001
WORKDIR /app

EXPOSE 8080
ENV AAAS_SERVICE=digit-7 \
    AAAS_DIGIT=7 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-7.db \
    AAAS_MIGRATIONS_DIR=/app/migrations \
    ERL_LIBS=/app/lib

# +sbwt none (and its dirty variants): schedulers do not busy-wait for
# work, which only burns the container's CPU quota on an idle service.
# +P 4096 and +Q 1024: the process and port tables (sockets are ports) are
# sized for 256 connections with ample margin instead of the defaults of
# about one million processes and 65 536 ports, which saves about 17 MB.
ENTRYPOINT ["/usr/local/lib/erlang/bin/erl", "+sbwt", "none", "+sbwtdcpu", "none", \
            "+sbwtdio", "none", "+P", "4096", "+Q", "1024", "-noshell", \
            "-eval", "digit7@@main:run(digit7)", "-extra"]
