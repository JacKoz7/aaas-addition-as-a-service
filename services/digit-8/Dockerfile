# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-8
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-8 service (D with LDC,
#                  TCP sockets, SQLite). Stages: toolchain, lint, test,
#                  doc-coverage, api-docs, build and the minimal non-root
#                  runtime image used by Compose.
# Related Docs:    services/digit-8/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022, ADR-0030
#
# Stage contract (used by services/digit-8/Makefile and the root Makefile):
#   base      — Alpine 3.24 with LDC 1.42 (the LLVM D compiler; DMD has no
#               arm64 build), dub, the C toolchain LDC links with, and the
#               SQLite and zlib libraries (zlib: Phobos's std.zlib, linked
#               into every static executable).
#   dtools    — dfmt and D-Scanner 0.15.2, built from their dub packages
#               (Alpine packages neither, and their releases have no arm64
#               binaries).
#   toolchain — base with dfmt and D-Scanner and the sources; the package
#               has no dub dependencies to fetch.
#   lint      — dfmt (the formatted text must equal the file), D-Scanner,
#               and builds of every target with warnings and deprecations
#               as errors.
#   test      — `dub test`: the unittest blocks of the sources (documented
#               examples) and of tests/, against the real migrations.
#   doc-coverage — the compiler's JSON description of every declaration
#               checked by tools/doc_coverage.d, and ddoc with warnings as
#               errors.
#   api-docs  — ddoc HTML of the src modules with an index.html, exported
#               by `make api-docs` and published in the portal (ADR-0010).
#   build     — the stripped static executable in /out.
#   busybox   — the static busybox binary (wget for the Compose healthcheck).
#   runtime   — scratch with the executable, the migrations and busybox as
#               wget, user 10001, port 8080 (HTTP only: the digit contract
#               has no gRPC, CLAUDE.md 4.4).

FROM alpine:3.24.3 AS base
RUN apk add --no-cache ldc=1.42.0-r0 dub=1.41.0-r2 gcc=15.2.0-r5 musl-dev=1.2.6-r3 \
        sqlite-dev=3.53.4-r0 sqlite-static=3.53.4-r0 zlib-static=1.3.2-r1

FROM base AS dtools
# dub resolves each tool's dependencies from the dub.selections.json of
# its package; the dub cache stays in this stage.
RUN export HOME=/tmp/dub \
    && dub fetch dfmt@0.15.2 \
    && dub fetch dscanner@0.15.2 \
    && dub build dfmt@0.15.2 --build=release \
    && dub build dscanner@0.15.2 --build=release \
    && mkdir -p /out \
    && cp /tmp/dub/.dub/packages/dfmt/0.15.2/dfmt/bin/dfmt \
        /tmp/dub/.dub/packages/dscanner/0.15.2/dscanner/bin/dscanner /out/ \
    && strip /out/dfmt /out/dscanner

FROM base AS toolchain
COPY --from=dtools /out/ /usr/local/bin/
WORKDIR /src
COPY . .

FROM toolchain AS lint
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# dfmt reads its settings from .editorconfig; a file whose formatted text
# differs from it fails the stage.
RUN for file in $(find src tests tools -name '*.d' | sort); do \
        dfmt "$file" | cmp -s "$file" - \
            || { echo "lint: $file is not formatted (make fmt-digit-8)"; exit 1; }; \
    done \
    && dscanner --styleCheck --config dscanner.ini src tests tools \
    && dub build --build=debug \
    && dub build --config=unittest --build=unittest \
    && ldc2 -w -de -o- tools/doc_coverage.d \
    && echo "lint: dfmt, D-Scanner and the compiler (warnings as errors) clean"

FROM toolchain AS test
RUN dub test

FROM toolchain AS doc-coverage
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# -D fills the comment field of each declaration in the -X description;
# -w makes ddoc's warnings (for example a Params entry that names no
# parameter) errors.
RUN find src tests tools -name '*.d' -print0 | sort -z \
    | xargs -0 ldc2 -w -o- -unittest -preview=dip1000 -preview=in -Isrc -Itests \
        -D -Dd=/tmp/ddoc -X -Xf=/tmp/description.json \
    && ldc2 -unittest -run tools/doc_coverage.d \
    && ldc2 -run tools/doc_coverage.d /tmp/description.json \
    && echo "doc-coverage: 100% (every declaration documented; ddoc without warnings)"

FROM toolchain AS api-docs-build
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# The modules of the service with ddoc's default page style; ddoc leaves
# private declarations out (the coverage gate checks them). The portal
# serves the export under api/digit-8/ (ADR-0010).
RUN mkdir -p /api-docs \
    && find src -name '*.d' -print0 | sort -z \
    | xargs -0 ldc2 -w -o- -preview=dip1000 -preview=in -Isrc -D -Dd=/api-docs \
    && { printf '%s\n' '<!doctype html>' '<meta charset="utf-8">' '<title>digit-8 API</title>' \
            '<h1>digit-8 API</h1>' '<p>ddoc reference of the digit-8 service (D).</p>' '<ul>'; \
        for path in /api-docs/*.html; do \
            page="${path##*/}"; \
            printf '<li><a href="%s">digit8.%s</a></li>\n' "$page" "${page%.html}"; \
        done; \
        printf '%s\n' '</ul>'; } > /tmp/index.html \
    && mv /tmp/index.html /api-docs/index.html

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
# /out/data: the mount point of the volume, owned by the runtime user.
RUN mkdir -p /out/data \
    && dub build --build=production \
    && strip -o /out/digit-8 build/digit-8

# Static busybox (musl); its wget applet answers the Compose healthcheck.
FROM busybox:1.37.0-musl AS busybox

# The executable is static, so the image needs no C library.
FROM scratch AS runtime

LABEL org.opencontainers.image.title="digit-8" \
      org.opencontainers.image.description="AaaS digit-8 service (D): Authoritative source for the value and successor of digit 8." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

COPY --from=busybox /bin/busybox /usr/local/bin/wget
COPY --from=build --chown=10001:10001 /out/data /data
WORKDIR /app
COPY --from=build /out/digit-8 /app/digit-8
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=digit-8 \
    AAAS_DIGIT=8 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-8.db \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/digit-8"]
