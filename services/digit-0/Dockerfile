# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-0
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-0 service (C, SQLite,
#                  libmicrohttpd). Stages: toolchain, lint, test,
#                  doc-coverage, api-docs, build and the minimal non-root
#                  runtime image used by Compose.
# Related Docs:    services/digit-0/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022
#
# Stage contract (used by services/digit-0/Makefile and the root Makefile):
#   toolchain — Alpine 3.22 with the C compiler, the SQLite and
#               libmicrohttpd headers, clang-format, clang-tidy and Doxygen,
#               all pinned.
#   lint      — clang-format in check mode, clang-tidy (findings are
#               errors) and a compile with -Werror.
#   test      — the unit tests of tests/ against the real migrations.
#   doc-coverage — Doxygen with every undocumented definition (static ones
#               included) as an error: 100% or the stage fails.
#   api-docs  — Doxygen HTML with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — the release binary in /out.
#   runtime   — Alpine 3.22 with the SQLite and libmicrohttpd libraries,
#               non-root user, port 8080 (HTTP only: the digit contract has
#               no gRPC, CLAUDE.md 4.4).

FROM alpine:3.22.2 AS toolchain
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# clang20 brings clang-format; clang20-extra-tools brings clang-tidy. GCC
# (build-base) compiles; clang only lints and formats.
RUN apk add --no-cache build-base=0.5-r3 sqlite-dev=3.49.2-r1 libmicrohttpd-dev=1.0.1-r1 \
        clang20=20.1.8-r0 clang20-extra-tools=20.1.8-r0 doxygen=1.13.2-r0
WORKDIR /src
# Compiler flags of every stage: C17, all warnings as errors, POSIX 2008
# (scandir, gmtime_r, sigwait).
ENV CFLAGS="-std=c17 -O2 -Wall -Wextra -Wpedantic -Werror -D_POSIX_C_SOURCE=200809L -D_DEFAULT_SOURCE"
COPY . .

FROM toolchain AS lint
RUN clang-format --dry-run --Werror src/*.c src/*.h tests/*.c \
    && clang-tidy --quiet src/*.c tests/*.c -- ${CFLAGS} \
    && gcc ${CFLAGS} -fsyntax-only src/*.c tests/*.c \
    && echo "lint: clang-format, clang-tidy and gcc -Werror clean"

FROM toolchain AS test
RUN gcc ${CFLAGS} -o /tmp/test_digit tests/test_digit.c src/api.c src/log.c src/metrics.c src/store.c \
       src/trace.c -lsqlite3 \
    && /tmp/test_digit

FROM toolchain AS doc-coverage
RUN doxygen Doxyfile \
    && echo "doc-coverage: 100% (Doxygen, static definitions included, warnings are errors)"

FROM toolchain AS api-docs-build
# Inherited from toolchain; repeated so that hadolint sees pipefail (DL4006).
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN mkdir -p /api-docs \
    && (cat Doxyfile; echo "OUTPUT_DIRECTORY = /api-docs"; echo "HTML_OUTPUT = .") | doxygen -

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
RUN mkdir -p /out \
    && gcc ${CFLAGS} -o /out/digit-0 src/*.c -lsqlite3 -lmicrohttpd \
    && strip /out/digit-0

FROM alpine:3.22.2 AS runtime

LABEL org.opencontainers.image.title="digit-0" \
      org.opencontainers.image.description="AaaS digit-0 service (C): Authoritative source for the value and successor of digit 0." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

# Shared libraries of the binary. busybox (wget) serves the Compose
# healthcheck.
RUN apk add --no-cache sqlite-libs=3.49.2-r1 libmicrohttpd=1.0.1-r1 \
    && adduser -D -H -u 10001 -s /sbin/nologin digit \
    && mkdir -p /data \
    && chown 10001:10001 /data
WORKDIR /app
COPY --from=build /out/digit-0 /app/digit-0
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=digit-0 \
    AAAS_DIGIT=0 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-0.db \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/digit-0"]
