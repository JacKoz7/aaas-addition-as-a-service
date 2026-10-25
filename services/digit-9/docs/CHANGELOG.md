# Changelog — `digit-9`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-9/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-9` by git-cliff
(`make changelog-digit-9 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [Unreleased]

## [0.1.0] — 2026-10-25

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 9,
  answered from the SQLite database on every request; `/next` answers the
  successor 0 with `carry: true`.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`) and 503, and from the
  service's own HTTP/1.1 server for 400 (malformed request), 413 (body
  above 64 KiB) and 431 (head above 8 KiB).
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 9.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM, SIGINT and SIGHUP.
- Racket 9.2 executable built by `raco exe`: an HTTP/1.1 server on
  Racket's TCP ports with one Racket thread and one custodian per
  connection, keep-alive, at most 256 connections, 10 s idle timeout, and
  SQLite through the foreign function interface instead of Racket's `db`
  library (ADR-0031).
- A memory guard that runs a major garbage collection whenever the runtime
  holds 12 MiB more memory than after its previous collection.
- Unit tests (`raco test`: 225 tests, the examples of the doc comments
  included), fmt and review, and documentation coverage of 100% (every
  module-level definition, private ones included); API documentation
  rendered by Scribble from the doc comments.

### Business Impact

With digit nine, AaaS has a service for every digit, and the first one
whose answer carries: `9 + 1` now has an authoritative source for both the
`0` it leaves and the carry it passes to the next position.
