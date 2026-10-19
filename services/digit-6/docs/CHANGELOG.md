# Changelog — `digit-6`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-6/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-6` by git-cliff
(`make changelog-digit-6 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [0.1.0] — 2026-10-19

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 6,
  answered from the SQLite database on every request.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`) and 503, and from the
  service's own HTTP/1.1 server for 400 (malformed request), 413 (body
  above 64 KiB) and 431 (head above 8 KiB).
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 6.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM and SIGINT.
- Swift 6.3 executable without package dependencies: an HTTP/1.1 server
  on POSIX sockets with one thread per connection, keep-alive, at most
  256 connections, 10 s idle timeout (ADR-0028).
- Unit tests (swift-testing, 23 tests), swift format, warnings as errors,
  and documentation coverage of 100% (symbol graphs down to private
  access, and DocC with warnings as errors).

### Business Impact

Digit six, the first perfect number, now runs on a service with no
third-party dependencies at all. Its build fetches nothing from the
internet, so it builds as well on a slow connection as on a fast one.
Idle, it uses 1.1 MiB; of the seven digits delivered so far only the
Fortran `digit-2` uses less.
