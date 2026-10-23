# Changelog — `digit-7`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-7/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-7` by git-cliff
(`make changelog-digit-7 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [0.1.0] — 2026-10-23

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 7,
  answered from the SQLite database on every request.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`) and 503, and from the
  service's own HTTP/1.1 server for 400 (malformed request), 413 (body
  above 64 KiB) and 431 (head above 8 KiB).
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 7.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM through a `gen_event` handler written in
  Gleam.
- Gleam 1.19 package on Erlang/OTP 28: an HTTP/1.1 server on `gen_tcp`
  with one process per connection, keep-alive, at most 256 connections
  (tracked by an OTP actor), 10 s idle timeout, and one contract process
  that owns the database and the counters (ADR-0029).
- Unit tests (gleeunit, 56 tests), `gleam format --check`, warnings as
  errors, and documentation coverage of 100% (`dev/doc_coverage.gleam` on
  the `glance` parser, and `gleam docs build`).

### Business Impact

Digit seven now runs on the virtual machine built for telephone
exchanges, so each connection lives in its own process: a fault in one
conversation with a caller cannot disturb the others. AaaS's most
fortunate digit is also its most fault-tolerant.
