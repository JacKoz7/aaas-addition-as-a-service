# Changelog — `digit-0`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-0/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-0` by git-cliff
(`make changelog-digit-0 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [0.1.0] — 2026-10-18

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 0,
  answered from the SQLite database on every request.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`) and 503.
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 0.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM.
- Unit tests (52 checks), clang-format, clang-tidy, Doxygen coverage 100%.

### Business Impact

We are proud to introduce the first member of the AaaS digit family. With
`digit-0`, the number zero is no longer an implementation detail of a CPU
but a governed, observable, contract-tested enterprise asset, ready to serve
every successor step that touches a zero from P2.13 onwards, and setting the
standard the nine other digits will follow.
