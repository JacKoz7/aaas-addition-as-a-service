# Changelog — `carry`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `carry/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `carry` by git-cliff
(`make changelog-carry VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [Unreleased]

## [0.1.0] — 2026-10-26

### Added

- gRPC `aaas.carry.v1.CarryService/Propagate` on port 9090: the carry is
  propagated through `GET /next` of the digit services, with timeouts,
  retries and a check of every answer against the digit contract;
  statuses `INVALID_ARGUMENT`, `UNAVAILABLE` and `INTERNAL`.
- The propagation log in Mnesia (`carry_propagations`, disc only): a
  retried call answers the stored digits and republishes the stored event;
  JSON migrations with table documentation; hourly retention
  (`AAAS_RETENTION_HOURS`, default 24 h).
- The event `aaas.carry.propagated.v1`, acknowledged by all in-sync
  replicas before the call is answered.
- `GET /health` (database and broker checks) and `GET /metrics`
  (`carry_propagations_total`, `carry_propagation_duration_seconds`,
  `carry_digit_calls_total`, `carry_dependency_failures_total`,
  `carry_retention_deleted_total`, `carry_build_info`).
- JSON log lines with the task and trace identifiers; graceful shutdown on
  SIGTERM.

### Business Impact

Numbers ending in 9 can now be incremented by the Peano arithmetic
without a single native addition: the carry reaches every higher digit
through the service that owns it. Customers will notice from P2.13b, when
the successor starts relying on it.
