# Changelog — `digit-3`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-3/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-3` by git-cliff
(`make changelog-digit-3 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [0.1.0] — 2026-10-18

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 3,
  answered from the SQLite database on every request.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`), 413 (body above 64 KiB)
  and 503.
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 3.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM.
- Free Pascal 3.2.2 with the fcl-web `TFPHttpServer`, one thread per
  connection, a 2 s read timeout (ADR-0025).
- Unit tests (fpcunit, 8 tests), pasfmt, fpc with warnings, notes and hints
  as errors, PasDoc documentation coverage 100%.

### Business Impact

Named after Blaise Pascal, whose Pascaline added numbers mechanically in
1642, `digit-3` brings 384 years of arithmetic heritage to AaaS. The digit
three now enjoys the same governed contract, observability and
documentation as its siblings, in a distroless image a fraction of the
size of its first draft.
