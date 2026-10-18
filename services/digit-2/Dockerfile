# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-2
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-2 service (Fortran 2018,
#                  SQLite, an HTTP server over POSIX sockets). Stages:
#                  toolchain, lint, test, doc-coverage, api-docs, build and
#                  the minimal non-root runtime image used by Compose.
# Related Docs:    services/digit-2/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022, ADR-0024
#
# Stage contract (used by services/digit-2/Makefile and the root Makefile):
#   toolchain — Alpine 3.22 with gfortran 14 and the SQLite headers (pinned)
#               plus FORD and fprettify in a virtual environment with every
#               Python package pinned.
#   lint      — fprettify in check mode (its warnings included) and a
#               full compile and link of the service and the tests with
#               every gfortran warning an error (code generation warnings
#               such as -Wtrampolines need more than -fsyntax-only).
#   test      — the unit tests of tests/ against the real migrations, with
#               all run-time checks (-fcheck=all).
#   doc-coverage — FORD with `warn: true`: any undocumented entity fails.
#   api-docs  — FORD HTML with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — the release binary in /out.
#   runtime   — Alpine 3.22 with libgfortran and the SQLite library,
#               non-root user, port 8080 (HTTP only: the digit contract has
#               no gRPC, CLAUDE.md 4.4).

FROM alpine:3.22.2 AS toolchain
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# gfortran compiles; python3 hosts FORD (documentation) and fprettify
# (formatter), which are not packaged by Alpine. FORD's dependencies are
# pinned too, so that the documentation check is reproducible.
RUN apk add --no-cache gfortran=14.2.0-r6 musl-dev=1.2.5-r12 sqlite-dev=3.49.2-r1 python3=3.12.15-r0 \
    && python3 -m venv /opt/tools \
    && /opt/tools/bin/pip install --no-cache-dir \
        FORD==7.0.13 fprettify==0.3.7 beautifulsoup4==4.15.0 ConfigArgParse==1.8.0 graphviz==0.20.3 \
        Jinja2==3.1.6 Markdown==3.4.4 markdown-include==0.7.2 markdown-it-py==4.2.0 MarkupSafe==3.0.4 \
        mdurl==0.1.2 pcpp==1.30 Pygments==2.21.0 python-markdown-math==0.9 rich==15.0.0 soupsieve==3.0.3 \
        toposort==1.7 tqdm==4.70.1 typing_extensions==4.16.0
ENV PATH="/opt/tools/bin:${PATH}"
WORKDIR /src
# Compiler flags of every stage: Fortran 2018, every warning an error,
# implicit typing and implicit interfaces forbidden, array bounds checked.
ENV FFLAGS="-std=f2018 -O2 -Wall -Wextra -Wpedantic -Wimplicit-interface -Wimplicit-procedure -Wconversion -Werror -fimplicit-none -fcheck=bounds"
# Module order: each file uses only the modules before it.
ENV MODULES="src/posix.f90 src/sqlite.f90 src/log.f90 src/trace.f90 src/store.f90 src/metrics.f90 src/api.f90 src/http.f90 src/service.f90"
COPY . .

FROM toolchain AS lint
RUN fprettify --indent 2 --line-length 120 --diff ${MODULES} src/main.f90 tests/*.f90 > /tmp/format.diff 2>&1 \
    && if [ -s /tmp/format.diff ]; then cat /tmp/format.diff; exit 1; fi \
    && mkdir -p /tmp/mod \
    && gfortran ${FFLAGS} -J /tmp/mod -o /tmp/digit-2 ${MODULES} src/main.f90 -lsqlite3 \
    && gfortran ${FFLAGS} -J /tmp/mod -o /tmp/test_digit ${MODULES} tests/test_digit.f90 -lsqlite3 \
    && echo "lint: fprettify and gfortran -Werror clean"

FROM toolchain AS test
RUN mkdir -p /tmp/mod \
    && gfortran ${FFLAGS} -fcheck=all -J /tmp/mod -o /tmp/test_digit ${MODULES} tests/test_digit.f90 -lsqlite3 \
    && /tmp/test_digit

FROM toolchain AS doc-coverage
RUN ford ford.md > /tmp/ford.log 2>&1 \
    && if grep -i "warning" /tmp/ford.log; then exit 1; fi \
    && echo "doc-coverage: 100% (FORD, private entities included, no warning)"

FROM toolchain AS api-docs-build
# Inherited from toolchain; repeated so that hadolint sees pipefail (DL4006).
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN ford --output_dir /api-docs ford.md > /tmp/ford.log 2>&1 || { cat /tmp/ford.log; exit 1; }

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
RUN mkdir -p /out /tmp/mod \
    && gfortran ${FFLAGS} -J /tmp/mod -o /out/digit-2 ${MODULES} src/main.f90 -lsqlite3 \
    && strip /out/digit-2

FROM alpine:3.22.2 AS runtime

LABEL org.opencontainers.image.title="digit-2" \
      org.opencontainers.image.description="AaaS digit-2 service (Fortran): Authoritative source for the value and successor of digit 2." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

# Shared libraries of the binary (Fortran runtime, SQLite). busybox (wget)
# serves the Compose healthcheck.
RUN apk add --no-cache libgfortran=14.2.0-r6 sqlite-libs=3.49.2-r1 \
    && adduser -D -H -u 10001 -s /sbin/nologin digit \
    && mkdir -p /data \
    && chown 10001:10001 /data
WORKDIR /app
COPY --from=build /out/digit-2 /app/digit-2
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=digit-2 \
    AAAS_DIGIT=2 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-2.db \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/digit-2"]
