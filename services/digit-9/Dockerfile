# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-9
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-9 service (Racket on Chez
#                  Scheme, TCP ports, SQLite through the foreign function
#                  interface). Stages: toolchain, lint, test, doc-coverage,
#                  api-docs, build and the minimal non-root runtime image used
#                  by Compose.
# Related Docs:    services/digit-9/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022, ADR-0031
#
# Stage contract (used by services/digit-9/Makefile and the root Makefile):
#   base      — Alpine 3.24 with Racket 9.2 (Alpine's minimal Racket CS; the
#               official Racket images are amd64 only) and the SQLite
#               library the service loads.
#   tools     — base with the packages of the build, lint, test and
#               documentation stages: raco exe and raco test (compiler-lib),
#               rackunit, Scribble and Typed Racket from the Racket 9.2
#               release catalog, the formatter fmt and the linter review from
#               pinned commits of their repositories.
#   toolchain — tools with the sources.
#   lint      — fmt (the formatted text must equal the file), a line limit
#               of 100, compilation of every module and review.
#   test      — `raco test tests`: the unit tests and the examples of the
#               doc comments.
#   doc-coverage — tools/doc-coverage.rkt on every module (100%).
#   api-docs  — the Scribble HTML rendered from the doc comments, exported
#               by `make api-docs` and published in the portal (ADR-0010).
#   build     — the executable of `raco exe`, packaged by `raco distribute`
#               with the Racket runtime it needs, in /out.
#   runtime   — Alpine with the shared libraries of the Racket runtime and
#               SQLite, user 10001, port 8080 (HTTP only: the digit contract
#               has no gRPC, CLAUDE.md 4.4).

FROM alpine:3.24.3 AS base
RUN apk add --no-cache racket=9.2-r0 sqlite-libs=3.53.4-r0

FROM base AS tools
# Packages of the Racket distribution come from the catalog of the 9.2
# release, so their versions match the runtime. fmt is installed without
# its documentation dependency (racket-doc, the whole Racket manual).
# review loads a table of modules of the full distribution when it
# starts; the packages of that table it does not otherwise need are
# installed as sources only (--no-setup: nothing is compiled), last, so no
# later setup compiles them (ADR-0031).
ARG RACKET_CATALOG=https://download.racket-lang.org/releases/9.2/catalog/
RUN raco pkg install --batch --no-docs --scope installation --auto --catalog "$RACKET_CATALOG" \
        compiler-lib rackunit-lib scribble-lib typed-racket-lib macro-debugger-text-lib \
    && raco pkg install --batch --no-docs --scope installation --deps force \
        "https://github.com/sorawee/pretty-expressive.git?path=pretty-expressive-lib#27e7be8016b38252a19f3620bc37539100b02503" \
        "https://github.com/sorawee/pretty-expressive.git?path=pretty-expressive#27e7be8016b38252a19f3620bc37539100b02503" \
        "https://github.com/sorawee/fmt.git#4e1ed68e596e656960b44a8244bb33eb4e65ec64" \
    && raco pkg install --batch --no-docs --scope installation --deps fail \
        "https://github.com/Bogdanp/racket-review.git#ecb1968f12b485b5387f66bbd9220f191d136d84" \
    && raco pkg install --batch --no-docs --no-setup --scope installation --deps force \
        --catalog "$RACKET_CATALOG" \
        errortrace-lib scheme-lib gui-lib slideshow-lib string-constants-lib wxme-lib \
    && rm -rf /root/.cache /root/.local/share/racket/9.2/download-cache

FROM tools AS toolchain
WORKDIR /src
COPY . .

FROM toolchain AS lint
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN for file in src/digit9/*.rkt tools/*.rkt tests/*.rkt; do \
        raco fmt --width 100 "$file" | cmp -s "$file" - \
            || { echo "lint: $file is not formatted (make fmt-digit-9)"; exit 1; }; \
    done \
    && awk 'length > 100 { print FILENAME ":" FNR ": line longer than 100 characters"; bad = 1 } \
            END { exit bad }' src/digit9/*.rkt tools/*.rkt tests/*.rkt \
    && raco make -v src/digit9/*.rkt tools/*.rkt tests/*.rkt \
    && raco review src/digit9/*.rkt tools/*.rkt tests/*.rkt \
    && echo "lint: fmt, line length, compilation and review clean"

FROM toolchain AS test
RUN raco make src/digit9/*.rkt tools/*.rkt tests/*.rkt && raco test tests

FROM toolchain AS doc-coverage
RUN raco make tools/doc-coverage.rkt \
    && racket tools/doc-coverage.rkt src/digit9/*.rkt tools/*.rkt tests/*.rkt \
    && echo "doc-coverage: 100% (every definition documented)"

FROM toolchain AS api-docs-build
# The modules of the service; the portal serves the export under
# api/digit-9/ (ADR-0010).
RUN raco make tools/api-docs.rkt && racket tools/api-docs.rkt /api-docs src/digit9/*.rkt

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM tools AS build
WORKDIR /src
COPY src/ src/
# /out/data: the mount point of the volume, owned by the runtime user.
RUN raco make src/digit9/main.rkt \
    && raco exe -o /tmp/digit-9 src/digit9/main.rkt \
    && mkdir -p /out && raco distribute /out/app /tmp/digit-9 \
    && mkdir -p /out/data

FROM alpine:3.24.3 AS runtime

LABEL org.opencontainers.image.title="digit-9" \
      org.opencontainers.image.description="AaaS digit-9 service (Racket): Authoritative source for the value and successor of digit 9 (next is 0 with carry)." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

# The shared libraries of the Racket runtime (ncurses, zlib, lz4) and the
# SQLite library the service loads; busybox wget (part of Alpine) answers
# the Compose healthcheck.
RUN apk add --no-cache libncursesw=6.6_p20260516-r0 zlib=1.3.2-r1 lz4-libs=1.10.0-r1 \
        sqlite-libs=3.53.4-r0 \
    && adduser -D -H -u 10001 -s /sbin/nologin digit

COPY --from=build /out/app /app
COPY --from=build --chown=10001:10001 /out/data /data
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001
WORKDIR /app

EXPOSE 8080
ENV AAAS_SERVICE=digit-9 \
    AAAS_DIGIT=9 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-9.db \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/bin/digit-9"]
