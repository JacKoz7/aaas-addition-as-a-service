# Dependencies — `digit-0`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-0` |
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
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 0 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry passing through a 0 waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing a 0 cannot be confirmed; the activity retries |

No service calls `digit-0` yet: the callers above arrive with the steps
named.

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `alpine` (toolchain and runtime base) | 3.22.2 | MIT (Alpine), various per package |
| GCC (`build-base`) | 0.5-r3 (GCC 14) | GPL-3.0 (compiler only; not linked) |
| SQLite (`sqlite-dev`, `sqlite-libs`) | 3.49.2-r1 | Public domain |
| libmicrohttpd (`libmicrohttpd-dev`, `libmicrohttpd`) | 1.0.1-r1 | LGPL-2.1+ (dynamically linked) |
| clang-format, clang-tidy (`clang20`, `clang20-extra-tools`) | 20.1.8-r0 | Apache-2.0 with LLVM exception (lint only) |
| Doxygen | 1.13.2-r0 | GPL-2.0 (documentation only) |
