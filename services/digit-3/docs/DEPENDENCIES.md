# Dependencies — `digit-3`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-3` |
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
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 3 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry passing through a 3 waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing a 3 cannot be confirmed; the activity retries |

No service calls `digit-3` yet: the callers above arrive with the steps
named.

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `debian` (toolchain base) | trixie-20261005-slim | Various per package |
| Free Pascal (`fp-compiler`, `fp-units-base`, `fp-units-fcl`, `fp-units-db`, `fp-units-net`) | 3.2.2+dfsg-46 | GPL-2.0 (compiler); RTL and FCL under the modified LGPL (static, linking exception) |
| C runtime start files (`libgcc-14-dev`) | 14.2.0-19 | GPL-3.0 with the GCC Runtime Library Exception (link time only) |
| SQLite (`libsqlite3-dev`; `libsqlite3.so.0` copied into the runtime) | 3.46.1-7+deb13u2 | Public domain |
| PasDoc | 0.16.0-2+b1 | GPL-2.0 (documentation only) |
| xmlstarlet | 1.6.1-4+b1 | MIT (documentation check only) |
| pasfmt (built in the `pasfmt` stage) | 0.7.0, commit `c3a34633` | LGPL-3.0 (lint only) |
| `rust` (pasfmt build) | 1.98.1-slim-trixie | MIT or Apache-2.0 (build only) |
| `gcr.io/distroless/cc-debian13` (runtime base) | nonroot, pinned by digest | Various (Debian packages) |
| `busybox` (static `wget` for the healthcheck) | 1.37.0-musl | GPL-2.0 |
