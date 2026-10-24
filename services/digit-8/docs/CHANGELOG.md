# Changelog — `digit-8`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `digit-8/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `digit-8` by git-cliff
(`make changelog-digit-8 VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [Unreleased]

## [0.1.0] — 2026-10-24

### Added

- `GET /value` and `GET /next` of `contracts/http/digit.yaml` for digit 8,
  answered from the SQLite database on every request.
- `GET /health` (database check) and `GET /metrics`
  (`digit_requests_total{digit,endpoint,outcome}`, `digit_build_info`).
- Problem details for 404, 405 (`Allow: GET`) and 503, and from the
  service's own HTTP/1.1 server for 400 (malformed request), 413 (body
  above 64 KiB) and 431 (head above 8 KiB).
- Migration runner with `schema_migrations`; migration
  `0001_digit.sql` with the seed of digit 8.
- Structured JSON logs with the caller's trace from `traceparent`;
  graceful shutdown on SIGTERM and SIGINT.
- D executable (LDC 1.42) without dub dependencies: an HTTP/1.1 server on
  Phobos's TCP sockets with one thread per connection, keep-alive, at most
  256 connections, 10 s idle timeout; ended connection threads are joined
  at once (ADR-0030). Linked statically and shipped on `scratch`.
- Unit tests (`dub test`: 61 unittest blocks, documented examples
  included), dfmt and D-Scanner, warnings and deprecations as errors, and
  documentation coverage of 100% (the compiler's JSON description of every
  declaration, private ones included, and ddoc with warnings as errors).

### Business Impact

Digit eight, the only digit whose successor is also the largest digit,
ships in an image of 6.49 MB, the smallest of the nine digit services
delivered so far, with no C library, shell or package manager inside it.
Idle, it uses 3.2 MiB.
