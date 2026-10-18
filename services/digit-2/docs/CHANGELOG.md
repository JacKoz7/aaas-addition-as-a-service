# Changelog — `digit-2`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-2/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-2` by git-cliff
(`make changelog-digit-2 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [0.1.0] — 2026-10-18

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 2,
  answered from the SQLite database on every request.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`) and 503, plus 400 and 431
  for unreadable or oversized request heads.
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 2.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM.
- An HTTP/1.1 server written in Fortran over POSIX sockets
  (ISO_C_BINDING), one request per connection (ADR-0024).
- Unit tests (67 checks), fprettify, gfortran warnings as errors, FORD
  documentation coverage 100%.

### Business Impact

`digit-2` brings the most venerable language of scientific computing to the
AaaS digit family. FORTRAN has been adding numbers since 1957; with
`digit-2` it finally does so through a governed HTTP contract, without a
wrapper, and with a documentation coverage that the original IBM 704 team
could only dream of.
