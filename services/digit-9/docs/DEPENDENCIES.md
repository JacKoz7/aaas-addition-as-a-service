# Dependencies — `digit-9`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `digit-9` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-25 |

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
| `successor` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | Every successor step on a units digit 9 waits and retries; the addition is delayed, not wrong |
| `carry` (from P2.13) | HTTP `GET /next` | `contracts/http/digit.yaml` | A carry that reaches a 9 (and continues to the next position) waits and retries |
| `saga-orchestrator` (from P3.3) | HTTP `GET /value` (`resolveDigits`) | `contracts/http/digit.yaml` | Operands containing a 9 cannot be confirmed; the activity retries |

No service calls `digit-9` yet: the callers above arrive with the steps
named.

## 3. Build-Time and Runtime Dependencies

The service uses only the Racket base library at runtime (`racket/base`,
`racket/tcp`, `racket/string`, `racket/list` and `ffi/unsafe`); SQLite is
reached through the foreign function interface (`src/digit9/sqlite.rkt`,
ADR-0031). Racket's `db` library is not used.

| Dependency | Version | Used In | Licence |
| --- | --- | --- | --- |
| `alpine` (base of every stage) | 3.24.3 | Toolchain and runtime | MIT (Alpine scripts); packages as below |
| Racket CS (`racket`: Racket on Chez Scheme, minimal distribution) | 9.2-r0 | Toolchain; its runtime (`racketcs-9.2`, with the boot files) is copied into the runtime image by `raco distribute` | Apache-2.0 OR MIT |
| `ncurses`, `zlib`, `lz4` libraries (`libncursesw`, `zlib`, `lz4-libs`, needed by the Racket runtime) | 6.6_p20260516-r0, 1.3.2-r1, 1.10.0-r1 | Runtime | MIT-style (ncurses), Zlib, BSD-2-Clause |
| SQLite (`sqlite-libs`, `libsqlite3.so.0`, loaded at start-up) | 3.53.4-r0 | Toolchain and runtime | Public domain |
| `busybox` (`wget` for the healthcheck; part of Alpine) | 1.37.0 | Runtime | GPL-2.0 |
| compiler-lib (`raco exe`, `raco distribute`, `raco test`) | Racket 9.2 release catalog | Build and test | Apache-2.0 OR MIT |
| rackunit-lib (unit tests) | Racket 9.2 release catalog | Test | Apache-2.0 OR MIT |
| scribble-lib (API documentation) | Racket 9.2 release catalog | API documentation | Apache-2.0 OR MIT; parts CC-BY-3.0 and LPPL |
| typed-racket-lib, macro-debugger-text-lib (needed by review) | Racket 9.2 release catalog | Lint | Apache-2.0 OR MIT |
| errortrace-lib, scheme-lib, gui-lib, slideshow-lib, string-constants-lib, wxme-lib (sources only, not compiled; named by review's table of modules) | Racket 9.2 release catalog | Lint | Apache-2.0 OR MIT |
| fmt (formatter, `raco fmt`) and pretty-expressive | Git commits `4e1ed68` and `27e7be8` | Lint (`make fmt-digit-9`) | Apache-2.0 OR MIT |
| review (linter, `raco review`) | Git commit `ecb1968` | Lint | BSD-3-Clause |

The runtime image holds the executable (the modules of the service and the
Racket libraries it uses, compiled and embedded by `raco exe`), the Racket
runtime, the libraries above, the migrations and busybox; it has no Racket
compiler, package manager or collection directory.
