# Dependencies — `digit-5`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-5` |
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
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 5 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry passing through a 5 waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing a 5 cannot be confirmed; the activity retries |

No service calls `digit-5` yet: the callers above arrive with the steps
named.

## 3. Build-Time and Runtime Dependencies

Dart packages are pinned to exact versions in `pubspec.yaml` and locked,
with their transitive dependencies and checksums, in `pubspec.lock`.

| Dependency | Version | Used In | Licence |
| --- | --- | --- | --- |
| `dart` (Dart SDK image, Debian 13) | 3.13.4 | Toolchain; `/runtime` (glibc, loader) copied into the runtime | BSD-3-Clause (SDK); various (Debian packages) |
| SQLite (`libsqlite3-0`, `libsqlite3-dev`) | 3.46.1-7+deb13u2 | Tests; the library copied into the runtime | Public domain |
| sqlite3 (Dart package, FFI binding; loads the system library) | 3.7.0 | Compiled into the executable | MIT |
| ffi, collection, meta, path, typed_data, web, crypto (sqlite3 dependencies) | see `pubspec.lock` | Compiled into the executable | BSD-3-Clause |
| test | 1.32.0 | Tests | BSD-3-Clause |
| lints | 6.1.0 | Lint | BSD-3-Clause |
| analyzer | 14.4.0 | Documentation coverage tool | BSD-3-Clause |
| `busybox` (static `wget` for the healthcheck) | 1.37.0-musl | Runtime | GPL-2.0 |
