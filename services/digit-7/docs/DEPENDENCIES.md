# Dependencies — `digit-7`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-7` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-23 |

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
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 7 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry passing through a 7 waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing a 7 cannot be confirmed; the activity retries |

No service calls `digit-7` yet: the callers above arrive with the steps
named.

## 3. Build-Time and Runtime Dependencies

The Hex packages are locked to exact versions and checksums by
`manifest.toml`; `gleam deps download` verifies them (ADR-0029).

| Dependency | Version | Used In | Licence |
| --- | --- | --- | --- |
| `erlang` (Erlang/OTP image, Alpine 3.24) | 28.5.0.8-alpine | Toolchain: the BEAM, rebar3 (builds the esqlite NIF); its erts, kernel and stdlib are copied into the runtime | Apache-2.0 |
| Gleam (musl binary, SHA-256 checked) | 1.19.2 | Toolchain: compiler, formatter, test runner, `gleam docs` | Apache-2.0 |
| `build-base` (Alpine: gcc, make, musl-dev) | 0.5-r4 | Toolchain: compiles the esqlite NIF | Various (GPL-3.0 with exceptions for gcc) |
| `gleam_stdlib` | 1.0.5 | Runtime | Apache-2.0 |
| `gleam_erlang` (processes, subjects, atoms) | 1.3.0 | Runtime | Apache-2.0 |
| `gleam_otp` (actors: contract process, tracker) | 1.3.0 | Runtime | Apache-2.0 |
| `sqlight` (SQLite for Gleam) | 1.2.0 | Runtime | Apache-2.0 |
| `esqlite` (Erlang NIF with the SQLite amalgamation; SQLite is public domain) | 0.9.0 | Runtime | MIT |
| `pc` (rebar3 port compiler plugin, fetched by rebar3 for esqlite) | 1.15.0 | Toolchain | MIT |
| `envoy` (environment variables) | 1.2.0 | Runtime | Apache-2.0 |
| `gleeunit` | 1.11.0 | Tests | Apache-2.0 |
| `glance`, `glexer`, `splitter` (Gleam parser for the doc-coverage gate) | 7.0.0, 2.5.0, 1.3.0 | doc-coverage | Apache-2.0 |
| `alpine` (runtime base: musl, busybox `wget`) | 3.24.3 | Runtime | Various (Alpine packages) |
| `libncursesw`, `libstdc++`, `libgcc` (shared libraries of `beam.smp`) | 6.6_p20260516-r0, 15.2.0-r5, 15.2.0-r5 | Runtime | MIT-style (ncurses), GPL-3.0 with the GCC Runtime Library Exception |
