# digit-6

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Swift 6.3.3 (Swift runtime linked statically), POSIX sockets, SQLite 3.45 (C API) |
| Database | SQLite (embedded), volume `digit-6-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 6, built in Swift
to the reference behaviour of `digit-0` (ADR-0022, ADR-0028).

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7), the carry service
asks each digit it passes through, and the saga confirms the digits of the
operands (`resolveDigits`, step 6). Those callers arrive with P2.13 and
P3.3; until then the service runs but nobody calls it. If it is down, every
step that needs digit 6 waits and is retried by its caller: additions are
delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":6,"value":6}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":6,"next":7,"carry":false}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read. Outside the contract, the service's own
HTTP/1.1 server answers 400 for a malformed request, 413 for a request body
above 64 KiB and 431 for a request head above 8 KiB; these close the
connection. Connections are persistent (HTTP/1.1 keep-alive) and close after
10 s of silence. The full reference is [docs/API.md](docs/API.md); the
shared contract test is `make contract-digit-6`
([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-6.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 6, value 6, successor 7, no carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `src/DigitService/Store.swift`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test "answers from the
database, not from constants" proves. The database does not grow; no
retention is needed.

## Code

The package has no dependencies besides the Swift toolchain and SQLite
(ADR-0028); its targets live in `src/` and `tests/`.

| File | Responsibility |
| --- | --- |
| `src/digit6/main.swift` | Configuration, start-up checks, SIGTERM and SIGINT (`sigwait`) |
| `src/DigitService/Server.swift` | HTTP/1.1 server on POSIX sockets: one thread per connection, keep-alive, head and body limits, connection cap, graceful stop |
| `src/DigitService/Api.swift` | The contract as a function `(method, path) → Reply` |
| `src/DigitService/Store.swift` | SQLite (C API through `CSQLite`): open, migrate, read the row |
| `src/DigitService/Metrics.swift` | `digit_requests_total`, `digit_build_info` |
| `src/DigitService/Log.swift` | JSON log lines (`CLAUDE.md` 6.1), JSON escaping |
| `src/DigitService/Trace.swift` | `traceparent` parsing for the logs |
| `src/CSQLite/` | System library module of SQLite (`module.modulemap`, `shim.h`) |
| `tests/DigitServiceTests/DigitTests.swift` | swift-testing tests against the real migrations, including the HTTP transport through a connection double and over TCP |
| `tools/doc-coverage.swift` | Documentation coverage gate on the compiler's symbol graphs |
| `Package.swift` | Targets and compiler settings (warnings as errors) |

The runtime image is distroless (no shell): use `/usr/local/bin/wget`
(busybox) for manual checks inside the container.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-6` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `6` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-6.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |

## Running and testing

```sh
make build-digit-6         # image through Compose (root Makefile)
make test-digit-6          # swift-testing tests in the Dockerfile `test` stage
make lint-digit-6          # swift format lint --strict, swift build (warnings as errors)
make fmt-digit-6           # swift format in place
make doc-coverage-digit-6  # tools/doc-coverage.swift and DocC with warnings as errors (100%)
make api-docs-digit-6      # DocC static HTML to build/api-docs/digit-6
make up && make contract-digit-6   # shared contract test against the container
make logs SVC=digit-6
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md)
(reference behaviour), [ADR-0028](../../docs/adr/0028-digit-6-swift-without-dependencies.md)
(Swift implementation).
