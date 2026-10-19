# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-5
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-5 service (Dart 3.13,
#                  dart:io HttpServer, sqlite3). Stages: toolchain, lint,
#                  test, doc-coverage, api-docs, build and the minimal
#                  non-root runtime image used by Compose.
# Related Docs:    services/digit-5/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022, ADR-0027
#
# Stage contract (used by services/digit-5/Makefile and the root Makefile):
#   toolchain — the Dart SDK image with the packages of pubspec.lock and
#               the SQLite development package (libsqlite3.so).
#   lint      — dart format check and dart analyze with infos as errors.
#   test      — the package:test tests against the real migrations.
#   doc-coverage — tool/doc_coverage.dart (a /// comment on every
#               declaration, public and private) and dartdoc without
#               warnings.
#   api-docs  — dartdoc HTML with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — the AOT-compiled executable (dart build cli) in /out.
#   busybox   — the static busybox binary (wget for the Compose healthcheck).
#   runtime   — scratch with the Dart runtime files (/runtime of the SDK
#               image: glibc and the loader), the SQLite library, the
#               executable and busybox as wget, user 10001, port 8080
#               (HTTP only: the digit contract has no gRPC, CLAUDE.md 4.4).

FROM dart:3.13.4 AS toolchain
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
# The sqlite3 package loads the system SQLite by the name libsqlite3.so
# (pubspec.yaml, hooks), which only the -dev package provides; the image
# already holds libsqlite3-0 of the same version.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev=3.46.1-7+deb13u2 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --enforce-lockfile
COPY . .
RUN dart pub get --enforce-lockfile --offline

FROM toolchain AS lint
RUN dart format --output=none --set-exit-if-changed bin lib test tool \
    && dart analyze --fatal-infos \
    && echo "lint: dart format and dart analyze clean"

FROM toolchain AS test
RUN dart test --reporter expanded

FROM toolchain AS doc-coverage
# Repeated from the toolchain stage (the image keeps it) so that hadolint
# sees pipefail before the pipe into tee.
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN dart run tool/doc_coverage.dart bin/*.dart lib/*.dart lib/src/*.dart test/*.dart tool/*.dart \
    && dart doc --output /tmp/doc . 2>&1 | tee /tmp/dartdoc.log \
    && grep -q 'Found 0 warnings and 0 errors' /tmp/dartdoc.log \
    && echo "doc-coverage: 100% (every declaration documented; dartdoc without warnings)"

FROM toolchain AS api-docs-build
RUN dart doc --output /api-docs .

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
# `dart build cli` (not `dart compile exe`, which refuses packages with
# build hooks) writes the AOT executable; sqlite3 bundles no library
# because it loads the system one. /out/lib: the SQLite library for the
# runtime; /out/data: the mount point of the volume, owned by the runtime
# user.
RUN mkdir -p /out/lib /out/data \
    && dart build cli --target bin/digit5.dart --output /tmp/cli \
    && cp /tmp/cli/bundle/bin/digit5 /out/digit-5 \
    && cp -L /usr/lib/*-linux-gnu/libsqlite3.so.0 /out/lib/

# Static busybox (musl); its wget applet answers the Compose healthcheck.
FROM busybox:1.37.0-musl AS busybox

# scratch plus /runtime of the SDK image (the files an AOT executable
# needs: glibc, the loader, CA certificates), as the Dart image documents,
# instead of a Debian base (CLAUDE.md 6.6).
FROM scratch AS runtime

LABEL org.opencontainers.image.title="digit-5" \
      org.opencontainers.image.description="AaaS digit-5 service (Dart): Authoritative source for the value and successor of digit 5." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

COPY --from=toolchain /runtime/ /
COPY --from=busybox /bin/busybox /usr/local/bin/wget
# Installed under the name the sqlite3 package opens (libsqlite3.so).
COPY --from=build /out/lib/libsqlite3.so.0 /usr/lib/libsqlite3.so
COPY --from=build --chown=10001:10001 /out/data /data
COPY --from=build /out/digit-5 /app/digit-5
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=digit-5 \
    AAAS_DIGIT=5 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-5.db \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/digit-5"]
