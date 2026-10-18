# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-3
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-3 service (Free Pascal
#                  3.2.2, fcl-web, SQLite). Stages: toolchain, lint, test,
#                  doc-coverage, api-docs, build and the minimal non-root
#                  runtime image used by Compose.
# Related Docs:    services/digit-3/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022, ADR-0025
#
# Stage contract (used by services/digit-3/Makefile and the root Makefile):
#   pasfmt    — pasfmt 0.7.0 built from its release commit (no arm64
#               binary is published); only the binary is kept.
#   toolchain — Debian 13 (trixie) with Free Pascal 3.2.2 (compiler, RTL,
#               FCL units), PasDoc, xmlstarlet and the SQLite headers, all
#               pinned, plus pasfmt. Alpine does not package Free Pascal
#               (ADR-0025).
#   lint      — pasfmt check and a compile of the service and the tests
#               with warnings, notes and hints as errors.
#   test      — the fpcunit tests against the real migrations.
#   doc-coverage — PasDoc (simplexml, every visibility): any declaration
#               without a description fails; tools/implementation-doc-check.awk
#               does the same for unit-level constants and variables of the
#               implementation sections, which PasDoc does not read.
#   api-docs  — PasDoc HTML with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — the release binary in /out.
#   busybox   — the static busybox binary (wget for the Compose healthcheck).
#   runtime   — distroless Debian 13 cc (glibc, libgcc_s, no shell) with
#               the SQLite library of the toolchain and busybox as wget,
#               user 10001,
#               port 8080 (HTTP only: the digit contract has no gRPC,
#               CLAUDE.md 4.4).

# pasfmt: the formatter for Delphi and Free Pascal (LGPL-3.0). ptop, the
# formatter shipped with Free Pascal, mis-indents classes and constructors
# (ADR-0025).
FROM rust:1.98.1-slim-trixie AS pasfmt
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN apt-get update \
    && apt-get install -y --no-install-recommends git=1:2.47.3-0+deb13u1 \
    && rm -rf /var/lib/apt/lists/* \
    && cargo install --locked --root /opt/pasfmt \
        --git https://github.com/integrated-application-development/pasfmt \
        --rev c3a34633a91a94c3097b296a3664c94f56f00081 pasfmt

FROM debian:trixie-20261005-slim AS toolchain
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
# The metapackages pin the versioned Free Pascal 3.2.2 packages they depend
# on. fp-units-fcl brings fcl-web (TFPHttpServer) and fpcunit, fp-units-db
# the sqlite3 unit; libgcc-14-dev the C runtime start files (crtbegin.o)
# needed to link against libc (threads, SQLite), whose directory is added
# to /etc/fpc.cfg (Debian adds it only when gcc itself is installed).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        fp-compiler=3.2.2+dfsg-46 fp-units-base=3.2.2+dfsg-46 fp-units-fcl=3.2.2+dfsg-46 \
        fp-units-db=3.2.2+dfsg-46 fp-units-net=3.2.2+dfsg-46 \
        pasdoc=0.16.0-2+b1 xmlstarlet=1.6.1-4+b1 libsqlite3-dev=3.46.1-7+deb13u2 libgcc-14-dev=14.2.0-19 \
    && rm -rf /var/lib/apt/lists/* \
    && echo "-Fl$(ls -d /usr/lib/gcc/*-linux-gnu/14)" >> /etc/fpc.cfg
COPY --from=pasfmt /opt/pasfmt/bin/pasfmt /usr/local/bin/pasfmt
WORKDIR /src
# Compiler flags of every stage: Object Pascal mode, ansistrings, range and
# overflow checks, warnings, notes and hints shown and treated as errors.
ENV FPCFLAGS="-Mobjfpc -Sh -O2 -Cr -Co -vewnhi -Sewnh -Fusrc -Futests"
COPY . .

FROM toolchain AS lint
RUN mkdir -p /tmp/units \
    && pasfmt --mode check src tests \
    && fpc ${FPCFLAGS} -FU/tmp/units -o/tmp/digit3 src/digit3.lpr \
    && fpc ${FPCFLAGS} -FU/tmp/units -o/tmp/testrunner tests/testrunner.lpr \
    && echo "lint: pasfmt and fpc (warnings, notes and hints as errors) clean"

FROM toolchain AS test
RUN mkdir -p /tmp/units \
    && fpc ${FPCFLAGS} -FU/tmp/units -o/tmp/testrunner tests/testrunner.lpr \
    && /tmp/testrunner

FROM toolchain AS doc-coverage
RUN mkdir -p /tmp/xml \
    && pasdoc --format simplexml --output /tmp/xml --visible-members private,protected,public,published,automated \
        --verbosity 1 src/*.pas tests/TestDigit.pas \
    && missing=$(xmlstarlet sel -t -m '//*[(self::unit or self::function or self::constant or self::variable or self::structure or self::type or self::property) and not(description)]' -v 'concat(local-name(), " ", @name)' -n /tmp/xml/*.xml || true) \
    && if [ -n "$missing" ]; then echo "undocumented:"; echo "$missing"; exit 1; fi \
    && awk -f tools/implementation-doc-check.awk src/*.pas tests/*.pas \
    && echo "doc-coverage: 100% (PasDoc, every visibility; implementation constants and variables)"

FROM toolchain AS api-docs-build
RUN mkdir -p /api-docs \
    && pasdoc --format html --output /api-docs --title "digit-3 0.1.0" \
        --visible-members private,protected,public,published,automated --verbosity 1 src/*.pas tests/TestDigit.pas

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
# /out/lib: the SQLite library for the distroless runtime; /out/data: the
# mount point of the volume, owned by the runtime user.
RUN mkdir -p /out/lib /out/data /tmp/units \
    && fpc ${FPCFLAGS} -Xs -FU/tmp/units -o/out/digit-3 src/digit3.lpr \
    && cp -L /usr/lib/*-linux-gnu/libsqlite3.so.0 /out/lib/

# Static busybox (musl); its wget applet answers the Compose healthcheck.
FROM busybox:1.37.0-musl AS busybox

# Distroless base (glibc, CA certificates, no shell or package manager)
# instead of debian:trixie-slim (CLAUDE.md 6.6). The cc variant adds
# libgcc_s, which glibc loads when a thread exits (the server runs one
# thread per connection). Pinned by the digest of the multi-arch index of
# cc-debian13:nonroot.
FROM gcr.io/distroless/cc-debian13@sha256:e792ab3d241a468a4fd7519ddbbebe66b49b5f365771716ea688ad40b6c6f1c2 AS runtime

LABEL org.opencontainers.image.title="digit-3" \
      org.opencontainers.image.description="AaaS digit-3 service (Free Pascal): Authoritative source for the value and successor of digit 3." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

COPY --from=busybox /bin/busybox /usr/local/bin/wget
COPY --from=build /out/lib/libsqlite3.so.0 /usr/lib/libsqlite3.so.0
COPY --from=build --chown=10001:10001 /out/data /data
WORKDIR /app
COPY --from=build /out/digit-3 /app/digit-3
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=digit-3 \
    AAAS_DIGIT=3 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-3.db \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/digit-3"]
