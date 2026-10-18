# Changelog — `digit-4`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-4/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-4` by git-cliff
(`make changelog-digit-4 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [0.1.0] — 2026-10-18

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 4,
  answered from the SQLite database on every request.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`) and 503, and from the
  service's own HTTP/1.1 server for 400 (malformed request), 413 (body
  above 64 KiB) and 431 (head above 8 KiB).
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 4.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM and SIGINT.
- Lua 5.4 with an HTTP/1.1 server on cqueues: one coroutine per
  connection, keep-alive, at most 256 connections, 10 s idle timeout
  (ADR-0026).
- Unit tests (busted, 22 tests), StyLua, luacheck, and documentation
  coverage of 100% (tools/doc-coverage.lua and LDoc with warnings as
  errors).

### Business Impact

`digit-4` is the first digit service in an interpreted language, and it
keeps pace with its compiled siblings: 0.09 ms per call on a persistent
connection, level with the C++ `digit-1`. Lua, Portuguese for "moon", gives
the digit four its first lunar presence in the AaaS portfolio, at 21 MB of
image and under 4 MiB of memory.
