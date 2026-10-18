# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-4
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the digit-4 service (Lua 5.4,
#                  cqueues, lsqlite3). Stages: toolchain, lint, test,
#                  doc-coverage, api-docs, build and the minimal non-root
#                  runtime image used by Compose.
# Related Docs:    services/digit-4/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0022, ADR-0026
#
# Stage contract (used by services/digit-4/Makefile and the root Makefile):
#   toolchain — Alpine 3.22 with Lua 5.4, cqueues, lsqlite3 and luaposix
#               (the runtime modules) plus busted, luacheck, StyLua and
#               LDoc, all pinned.
#   lint      — StyLua check, luacheck and a bytecode compile of every file.
#   test      — the busted tests against the real migrations.
#   doc-coverage — tools/doc-coverage.lua (an LDoc comment above every
#               definition) and LDoc with warnings as errors.
#   api-docs  — LDoc HTML with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — the sources the runtime image runs, in /out.
#   runtime   — Alpine 3.22 with the Lua interpreter and the three runtime
#               modules, user 10001, port 8080 (HTTP only: the digit
#               contract has no gRPC, CLAUDE.md 4.4).

FROM alpine:3.22.2 AS toolchain
# luacheck runs on Lua 5.1 (its Alpine package), and checks the sources
# against the Lua 5.4 standard library (.luacheckrc).
RUN apk add --no-cache lua5.4=5.4.7-r0 lua5.4-cqueues=20200726-r6 lua5.4-lsqlite3=0.9.6-r2 \
        lua5.4-posix=36.3-r0 lua5.4-busted=2.2.0-r0 luacheck=0.26.1-r0 stylua=2.0.2-r0 ldoc=1.5.0-r0
WORKDIR /src
COPY . .

FROM toolchain AS lint
RUN stylua --check src tests tools .busted .luacheckrc config.ld \
    && luacheck src tests tools .busted .luacheckrc config.ld \
    && for f in src/main.lua src/digit/*.lua tests/*.lua tools/*.lua; do luac5.4 -p "$f" || exit 1; done \
    && echo "lint: stylua, luacheck and luac clean"

FROM toolchain AS test
RUN busted-5.4

FROM toolchain AS doc-coverage
RUN lua5.4 tools/doc-coverage.lua src/main.lua src/digit/*.lua tests/*.lua tools/*.lua \
    && ldoc --fatalwarnings -c config.ld -d /tmp/ldoc . \
    && echo "doc-coverage: 100% (every definition documented; LDoc without warnings)"

FROM toolchain AS api-docs-build
RUN ldoc --fatalwarnings -c config.ld -d /api-docs .

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
RUN mkdir -p /out/src/digit \
    && cp src/main.lua /out/src/ \
    && cp src/digit/*.lua /out/src/digit/

FROM alpine:3.22.2 AS runtime

LABEL org.opencontainers.image.title="digit-4" \
      org.opencontainers.image.description="AaaS digit-4 service (Lua): Authoritative source for the value and successor of digit 4." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

# The interpreter and the three modules the service requires; busybox wget
# (part of Alpine) answers the Compose healthcheck.
RUN apk add --no-cache lua5.4=5.4.7-r0 lua5.4-cqueues=20200726-r6 lua5.4-lsqlite3=0.9.6-r2 lua5.4-posix=36.3-r0 \
    && adduser -D -H -u 10001 -s /sbin/nologin digit \
    && mkdir -p /data \
    && chown 10001:10001 /data

WORKDIR /app
COPY --from=build /out/src/ /app/src/
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); /data (the SQLite volume) belongs to it.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=digit-4 \
    AAAS_DIGIT=4 \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/digit-4.db \
    AAAS_MIGRATIONS_DIR=/app/migrations \
    LUA_PATH="/app/src/?.lua;;"

ENTRYPOINT ["lua5.4", "/app/src/main.lua"]
