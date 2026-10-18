# Dependencies — `digit-2`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-2` |
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
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 2 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry passing through a 2 waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing a 2 cannot be confirmed; the activity retries |

No service calls `digit-2` yet: the callers above arrive with the steps
named.

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `alpine` (toolchain and runtime base) | 3.22.2 | MIT (Alpine), various per package |
| gfortran (`gfortran`, `musl-dev`) | 14.2.0-r6, 1.2.5-r12 | GPL-3.0 (compiler only; not linked) |
| Fortran runtime (`libgfortran`) | 14.2.0-r6 | GPL-3.0 with the GCC Runtime Library Exception (dynamically linked) |
| SQLite (`sqlite-dev`, `sqlite-libs`) | 3.49.2-r1 | Public domain |
| Python (`python3`, tools only) | 3.12.15-r0 | PSF-2.0 |
| FORD (documentation and coverage) | 7.0.13 | GPL-3.0 (documentation only) |
| fprettify (formatter) | 0.3.7 | GPL-3.0 (lint only) |

The Python packages FORD depends on are pinned in the Dockerfile.
