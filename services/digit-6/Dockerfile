# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-6
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-6 service (Swift 6.3,
#                  POSIX sockets, SQLite). Stages: toolchain, lint, test,
#                  doc-coverage, api-docs, build and the minimal non-root
#                  runtime image used by Compose.
# Related Docs:    services/digit-6/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022, ADR-0028
#
# Stage contract (used by services/digit-6/Makefile and the root Makefile):
#   toolchain — the Swift 6.3.3 image (Ubuntu 24.04) with the SQLite
#               headers; the package has no dependencies to fetch.
#   lint      — swift format lint (strict) and a build of every target
#               with warnings as errors.
#   test      — the swift-testing tests against the real migrations.
#   doc-coverage — symbol graphs down to private access checked by
#               tools/doc-coverage.swift, and DocC with warnings as errors.
#   api-docs  — DocC static HTML with an index.html at the root, exported
#               by `make api-docs` and published in the portal (ADR-0010).
#   build     — the release executable with the Swift runtime linked
#               statically, in /out.
#   busybox   — the static busybox binary (wget for the Compose healthcheck).
#   runtime   — distroless Debian 13 cc (glibc, libgcc_s, libstdc++, no
#               shell) with the SQLite library, the executable and
#               busybox as wget, user 10001, port 8080 (HTTP only: the
#               digit contract has no gRPC, CLAUDE.md 4.4).

FROM swift:6.3.3-noble AS toolchain
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev=3.45.1-1ubuntu2.8 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .

FROM toolchain AS lint
RUN swift format lint --strict --recursive Package.swift src tests tools \
    && swift build --build-tests \
    && echo "lint: swift format and the compiler (warnings as errors) clean"

FROM toolchain AS test
RUN swift test

FROM toolchain AS doc-coverage
# Symbol graphs of every declaration down to private access; the files of
# the service's modules are checked, those of the toolchain are not.
RUN swift build --build-tests -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir \
        -Xswiftc /tmp/graphs -Xswiftc -symbol-graph-minimum-access-level -Xswiftc private \
    && swift tools/doc-coverage.swift /src/ /tmp/graphs/DigitService*.symbols.json \
        /tmp/graphs/digit6*.symbols.json /tmp/graphs/DigitServiceTests*.symbols.json \
    && mkdir -p /tmp/public \
    && cp /tmp/graphs/DigitService.symbols.json /tmp/graphs/DigitService@*.symbols.json /tmp/public/ \
    && docc convert --additional-symbol-graph-dir /tmp/public --fallback-display-name DigitService \
        --fallback-bundle-identifier com.aaas.digit-6 --output-path /tmp/docc --warnings-as-errors \
    && echo "doc-coverage: 100% (every symbol documented; DocC without warnings)"

FROM toolchain AS api-docs-build
# The library documented down to private access, as the coverage gate
# checks it (an internal service: every declaration is its API). The portal
# serves the export under api/digit-6/ (ADR-0010), DocC's hosting base path;
# the root page redirects to the module page.
RUN swift build --target DigitService -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir \
        -Xswiftc /tmp/graphs -Xswiftc -symbol-graph-minimum-access-level -Xswiftc private \
    && mkdir -p /tmp/public \
    && cp /tmp/graphs/DigitService.symbols.json /tmp/graphs/DigitService@*.symbols.json /tmp/public/ \
    && docc convert --additional-symbol-graph-dir /tmp/public --fallback-display-name DigitService \
        --fallback-bundle-identifier com.aaas.digit-6 --output-path /tmp/docc --warnings-as-errors \
    && docc process-archive transform-for-static-hosting /tmp/docc --output-path /api-docs \
        --hosting-base-path api/digit-6 \
    && printf '%s\n' '<!doctype html>' '<meta charset="utf-8">' '<title>digit-6 API</title>' \
        '<meta http-equiv="refresh" content="0; url=documentation/digitservice/">' \
        '<a href="documentation/digitservice/">DigitService</a>' > /api-docs/index.html

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
# /out/lib: the SQLite library for the runtime; /out/data: the mount point
# of the volume, owned by the runtime user.
RUN mkdir -p /out/lib /out/data \
    && swift build -c release --static-swift-stdlib --product digit6 \
    && cp .build/release/digit6 /out/digit-6 \
    && cp -L /usr/lib/*-linux-gnu/libsqlite3.so.0 /out/lib/

# Static busybox (musl); its wget applet answers the Compose healthcheck.
FROM busybox:1.37.0-musl AS busybox

# Distroless base (glibc, no shell or package manager), the same image as
# digit-3 (ADR-0025). The cc variant adds libgcc_s and libstdc++, which the
# executable needs besides glibc (the Swift runtime is linked statically).
FROM gcr.io/distroless/cc-debian13@sha256:e792ab3d241a468a4fd7519ddbbebe66b49b5f365771716ea688ad40b6c6f1c2 AS runtime

LABEL org.opencontainers.image.title="digit-6" \
      org.opencontainers.image.description="AaaS digit-6 service (Swift): Authoritative source for the value and successor of digit 6." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

COPY --from=busybox /bin/busybox /usr/local/bin/wget
COPY --from=build /out/lib/libsqlite3.so.0 /usr/lib/libsqlite3.so.0
COPY --from=build --chown=10001:10001 /out/data /data
WORKDIR /app
COPY --from=build /out/digit-6 /app/digit-6
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=digit-6 \
    AAAS_DIGIT=6 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-6.db \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/digit-6"]
