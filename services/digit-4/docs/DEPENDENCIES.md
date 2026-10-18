# Dependencies — `digit-4`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-4` |
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
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 4 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry passing through a 4 waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing a 4 cannot be confirmed; the activity retries |

No service calls `digit-4` yet: the callers above arrive with the steps
named.

## 3. Build-Time and Runtime Dependencies

All packages come from Alpine 3.22 and are pinned in the Dockerfile.

| Dependency | Version | Used In | Licence |
| --- | --- | --- | --- |
| `alpine` (toolchain and runtime base) | 3.22.2 | All stages | Various per package |
| Lua (`lua5.4`) | 5.4.7-r0 | Toolchain, runtime | MIT |
| cqueues (`lua5.4-cqueues`; event loop, sockets, signals) | 20200726-r6 | Toolchain, runtime | MIT |
| lsqlite3 (`lua5.4-lsqlite3`; SQLite binding) | 0.9.6-r2 | Toolchain, runtime | MIT |
| luaposix (`lua5.4-posix`; clock, directory listing) | 36.3-r0 | Toolchain, runtime | MIT |
| SQLite (`sqlite-libs`, pulled by lsqlite3) | 3.49.2-r1 | Toolchain, runtime | Public domain |
| OpenSSL (`libssl3`, `libcrypto3`, pulled by cqueues) | 3.5.4-r0 | Toolchain, runtime (TLS is not used) | Apache-2.0 |
| busted (`lua5.4-busted`) | 2.2.0-r0 | Tests | MIT |
| luacheck | 0.26.1-r0 | Lint | MIT |
| StyLua | 2.0.2-r0 | Lint, `make fmt` | MPL-2.0 |
| LDoc | 1.5.0-r0 | Documentation | MIT |
