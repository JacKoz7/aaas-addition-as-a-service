# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-1
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-1 service (C++20, SQLite,
#                  cpp-httplib). Stages: toolchain, lint, test,
#                  doc-coverage, api-docs, build and the minimal non-root
#                  runtime image used by Compose.
# Related Docs:    services/digit-1/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022, ADR-0023
#
# Stage contract (used by services/digit-1/Makefile and the root Makefile):
#   toolchain — Alpine 3.22 with g++ 14, the SQLite headers, nlohmann-json,
#               doctest, clang-format, clang-tidy and Doxygen (all pinned),
#               plus the cpp-httplib header checked against its SHA-256.
#   lint      — clang-format in check mode, clang-tidy (findings are
#               errors) and a compile with -Werror.
#   test      — the doctest unit tests against the real migrations.
#   doc-coverage — Doxygen with every undocumented definition (private
#               members and anonymous namespaces included) as an error.
#   api-docs  — Doxygen HTML with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — the release binary in /out.
#   runtime   — Alpine 3.22 with the C++ runtime and SQLite libraries,
#               non-root user, port 8080 (HTTP only: the digit contract has
#               no gRPC, CLAUDE.md 4.4).

FROM alpine:3.22.2 AS toolchain
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# build-base brings g++ 14, which compiles; clang20 brings clang-format and
# clang20-extra-tools brings clang-tidy, which only lint and format.
# nlohmann-json and doctest are header-only.
RUN apk add --no-cache build-base=0.5-r3 sqlite-dev=3.49.2-r1 nlohmann-json=3.11.3-r0 doctest-dev=2.4.11-r0 \
        clang20=20.1.8-r0 clang20-extra-tools=20.1.8-r0 doxygen=1.13.2-r0
# cpp-httplib is not packaged by Alpine 3.22: the single header of the
# v0.26.0 release, verified by its SHA-256 (ADR-0023). In /usr/local/include
# it is a system header, so the strict warnings of this service do not
# apply to it.
ADD --checksum=sha256:4a42da28ce477d06f53942c172197d3b83b4fe42b7e37b8af78c70e063c06da7 \
    https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.26.0/httplib.h /usr/local/include/httplib.h
WORKDIR /src
# Compiler flags of every stage: C++20, all warnings as errors.
ENV CXXFLAGS="-std=c++20 -O2 -Wall -Wextra -Wpedantic -Wconversion -Wshadow -Werror"
COPY . .

FROM toolchain AS lint
RUN clang-format --dry-run --Werror src/*.cpp src/*.hpp tests/*.cpp \
    && clang-tidy --quiet src/*.cpp tests/*.cpp -- ${CXXFLAGS} \
    && g++ ${CXXFLAGS} -fsyntax-only src/*.cpp tests/*.cpp \
    && echo "lint: clang-format, clang-tidy and g++ -Werror clean"

FROM toolchain AS test
RUN g++ ${CXXFLAGS} -o /tmp/test_digit tests/test_digit.cpp src/api.cpp src/log.cpp src/metrics.cpp \
       src/store.cpp src/trace.cpp -lsqlite3 \
    && /tmp/test_digit

FROM toolchain AS doc-coverage
RUN doxygen Doxyfile \
    && echo "doc-coverage: 100% (Doxygen, private members included, warnings are errors)"

FROM toolchain AS api-docs-build
# Inherited from toolchain; repeated so that hadolint sees pipefail (DL4006).
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN mkdir -p /api-docs \
    && (cat Doxyfile; echo "OUTPUT_DIRECTORY = /api-docs"; echo "HTML_OUTPUT = .") | doxygen -

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
RUN mkdir -p /out \
    && g++ ${CXXFLAGS} -o /out/digit-1 src/*.cpp -lsqlite3 \
    && strip /out/digit-1

FROM alpine:3.22.2 AS runtime

LABEL org.opencontainers.image.title="digit-1" \
      org.opencontainers.image.description="AaaS digit-1 service (C++): Authoritative source for the value and successor of digit 1." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

# Shared libraries of the binary (C++ runtime, SQLite). busybox (wget)
# serves the Compose healthcheck.
RUN apk add --no-cache libstdc++=14.2.0-r6 libgcc=14.2.0-r6 sqlite-libs=3.49.2-r1 \
    && adduser -D -H -u 10001 -s /sbin/nologin digit \
    && mkdir -p /data \
    && chown 10001:10001 /data
WORKDIR /app
COPY --from=build /out/digit-1 /app/digit-1
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=digit-1 \
    AAAS_DIGIT=1 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-1.db \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/digit-1"]
