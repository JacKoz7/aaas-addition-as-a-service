# Dependencies — `digit-6`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-6` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-19 |

## 1. Upstream (this service depends on)

| Dependency | Kind | Contract | Effect of Failure |
| --- | --- | --- | --- |
| SQLite | Database (embedded) | Private schema in `migrations/` | `/value` and `/next` answer 503, `/health` 503; the container turns unhealthy |

The service calls no other service and consumes no events. From Phase 5 it
will read its configuration from `config-server` and register in
`service-discovery` (`CLAUDE.md` 3).

## 2. Downstream (depends on this service)

| Dependant | Kind | Contract | Effect of Our Failure |
| --- | --- | --- | --- |
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 6 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry passing through a 6 waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing a 6 cannot be confirmed; the activity retries |

No service calls `digit-6` yet: the callers above arrive with the steps
named.

## 3. Build-Time and Runtime Dependencies

The Swift package has no dependencies (`Package.swift`, ADR-0028).

| Dependency | Version | Used In | Licence |
| --- | --- | --- | --- |
| `swift` (Swift toolchain image, Ubuntu 24.04) | 6.3.3-noble | Toolchain: compiler, swift-format, swift-testing, DocC | Apache-2.0 with the Runtime Library Exception (the Swift runtime is linked statically into the executable) |
| SQLite (`libsqlite3-dev`; `libsqlite3.so.0` copied into the runtime) | 3.45.1-1ubuntu2.8 | Toolchain; runtime | Public domain |
| `gcr.io/distroless/cc-debian13` (runtime base: glibc, libgcc_s, libstdc++) | nonroot, pinned by digest | Runtime | Various (Debian packages) |
| `busybox` (static `wget` for the healthcheck) | 1.37.0-musl | Runtime | GPL-2.0 |
