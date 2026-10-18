# Dependencies — `digit-1`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-1` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |

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
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 1 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry passing through a 1, or writing the leading 1 of a result above 99 999, waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing a 1 cannot be confirmed; the activity retries |

No service calls `digit-1` yet: the callers above arrive with the steps
named.

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `alpine` (toolchain and runtime base) | 3.22.2 | MIT (Alpine), various per package |
| GCC, g++ (`build-base`) | 0.5-r3 (GCC 14) | GPL-3.0 (compiler only; not linked) |
| C++ runtime (`libstdc++`, `libgcc`) | 14.2.0-r6 | GPL-3.0 with the GCC Runtime Library Exception (dynamically linked) |
| SQLite (`sqlite-dev`, `sqlite-libs`) | 3.49.2-r1 | Public domain |
| cpp-httplib (`httplib.h`, header-only, compiled in) | 0.26.0, SHA-256 `4a42da28…63c06da7` | MIT |
| nlohmann-json (header-only, compiled in) | 3.11.3-r0 | MIT |
| doctest (`doctest-dev`, tests only) | 2.4.11-r0 | MIT |
| clang-format, clang-tidy (`clang20`, `clang20-extra-tools`) | 20.1.8-r0 | Apache-2.0 with LLVM exception (lint only) |
| Doxygen | 1.13.2-r0 | GPL-2.0 (documentation only) |
