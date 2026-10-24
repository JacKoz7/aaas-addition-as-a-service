# Dependencies — `digit-8`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-8` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-24 |

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
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 8 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry passing through an 8 waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing an 8 cannot be confirmed; the activity retries |

No service calls `digit-8` yet: the callers above arrive with the steps
named.

## 3. Build-Time and Runtime Dependencies

The dub package has no dependencies (`dub.sdl`, ADR-0030). SQLite is reached
through the C binding that ships with Phobos (`etc.c.sqlite3`).

| Dependency | Version | Used In | Licence |
| --- | --- | --- | --- |
| `alpine` (toolchain base) | 3.24.3 | Toolchain | MIT (Alpine scripts); packages as below |
| LDC (`ldc`, `ldc-static`: compiler, druntime and Phobos) | 1.42.0-r0 (DMD front end 2.112.1, LLVM 21) | Toolchain; druntime and Phobos are linked statically into the executable | BSD-3-Clause (LDC), BSL-1.0 (druntime, Phobos) |
| `dub` | 1.41.0-r2 | Toolchain: build and unit-test runner | MIT |
| `gcc`, `musl-dev` (the linker driver and C library LDC links with) | 15.2.0-r5, 1.2.6-r3 | Toolchain; musl is linked statically | GPL-3.0 with the GCC Runtime Library Exception; MIT (musl) |
| SQLite (`sqlite-dev`, `sqlite-static`) | 3.53.4-r0 | Toolchain; linked statically | Public domain |
| zlib (`zlib-static`, for Phobos's `std.zlib`) | 1.3.2-r1 | Toolchain; linked statically | Zlib |
| dfmt (formatter) | 0.15.2, built from its dub package | Lint (`make fmt-digit-8`) | BSL-1.0 |
| D-Scanner (linter) | 0.15.2, built from its dub package | Lint | BSL-1.0 |
| `busybox` (static `wget` for the healthcheck) | 1.37.0-musl | Runtime | GPL-2.0 |

The runtime image is `scratch`: it holds the static executable, the
migrations and busybox, and no C library.
