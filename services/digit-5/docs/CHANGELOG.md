# Changelog — `digit-5`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-5/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-5` by git-cliff
(`make changelog-digit-5 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [0.1.0] — 2026-10-19

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 5,
  answered from the SQLite database on every request.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`) and 503, and from the
  service's own HTTP/1.1 server for 400 (malformed request), 413 (body
  above 64 KiB) and 431 (head above 8 KiB).
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 5.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM and SIGINT.
- Dart 3.13 AOT executable with an HTTP/1.1 server on `dart:io` sockets:
  keep-alive, at most 256 connections, 10 s idle timeout (ADR-0027).
- Unit tests (package:test, 23 tests), dart format, dart analyze with
  infos as errors, and documentation coverage of 100%
  (tool/doc_coverage.dart and dartdoc without warnings).

### Business Impact

Digit five, the midpoint of the decimal system, now stands on a server
that withstood twelve rounds of 1 MB request heads from 512 connections
at a peak of 16.8 MiB. A first draft on the stock `dart:io` server fell
over to fewer than sixteen of them. AaaS chose resilience over
convenience, as befits the halfway mark of every digit.
