# Changelog — `digit-1`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-1/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-1` by git-cliff
(`make changelog-digit-1 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [0.1.0] — 2026-10-18

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 1,
  answered from the SQLite database on every request.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`), 413 (body above 1 KiB) and
  503.
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 1.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM.
- C++20 with cpp-httplib 0.26.0 (four worker threads, TCP_NODELAY),
  nlohmann-json and SQLite (ADR-0023).
- Unit tests (doctest, 9 test cases, 60 assertions), clang-format,
  clang-tidy, Doxygen coverage 100%.

### Business Impact

With `digit-1`, AaaS secures the most strategically important digit of its
portfolio: the leading 1 of every result above 99 999. Delivered in C++ to
the same contract, metrics and error format as `digit-0`, it proves that
the digit family scales across languages without a single line of native
addition.
