# digit-2

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Fortran 2018 (gfortran 14), own HTTP/1.1 server over POSIX sockets, SQLite 3.49 |
| Database | SQLite (embedded), volume `digit-2-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 2, built in
Fortran to the reference behaviour of `digit-0` (ADR-0022, ADR-0024).

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7), the carry service
asks each digit it passes through, and the saga confirms the digits of the
operands (`resolveDigits`, step 6). Those callers arrive with P2.13 and
P3.3; until then the service runs but nobody calls it. If it is down, every
step that needs digit 2 waits and is retried by its caller: additions are
delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":2,"value":2}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":2,"next":3,"carry":false}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read. The HTTP server adds, also as problem
details, 400 for a request head that is malformed or does not arrive within
500 ms and 431 for a head above 8 KiB. Every answer closes the connection
(`Connection: close`). The full reference is
[docs/API.md](docs/API.md); the shared contract test is
`make contract-digit-2` ([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-2.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 2, value 2, successor 3, no carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `src/store.f90`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test
`test_answers_come_from_the_database` proves. The database does not grow;
no retention is needed.

## Code

| File | Responsibility |
| --- | --- |
| `src/main.f90` | Program `digit_2`: calls `service_main` |
| `src/service.f90` | Configuration, start-up checks, request handler, shutdown |
| `src/http.f90` | HTTP/1.1 server: accept, read the head, parse, answer, close |
| `src/api.f90` | The contract as a function `(method, path) → reply` |
| `src/store.f90` | SQLite: open, migrate, read the row |
| `src/metrics.f90` | `digit_requests_total`, `digit_build_info` |
| `src/log.f90` | JSON log lines (`CLAUDE.md` 6.1), JSON escaping, UTC timestamps |
| `src/trace.f90` | `traceparent` parsing for the logs |
| `src/posix.f90` | `bind(C)` interfaces: sockets, poll, signals, clock, directories |
| `src/sqlite.f90` | `bind(C)` interfaces to the SQLite C API |
| `tests/test_digit.f90` | Unit tests against the real migrations |
| `ford.md` | FORD project file (API docs and coverage check) |

There is no wrapper process: the server, the digit logic and the database
access are Fortran; the C library is called through ISO_C_BINDING, and no
C source is compiled (ADR-0024). The server answers one connection at a
time and one request per connection; SIGTERM ends it within 200 ms.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-2` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `2` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-2.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |

## Running and testing

```sh
make build-digit-2         # image through Compose (root Makefile)
make test-digit-2          # unit tests in the Dockerfile `test` stage
make lint-digit-2          # fprettify check, gfortran -Werror (full compile)
make fmt-digit-2           # fprettify in place
make doc-coverage-digit-2  # FORD with warn: true, every entity documented (100%)
make api-docs-digit-2      # FORD HTML to build/api-docs/digit-2
make up && make contract-digit-2   # shared contract test against the container
make logs SVC=digit-2
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md)
(reference behaviour), [ADR-0024](../../docs/adr/0024-digit-2-fortran-http-server-without-wrapper.md)
(Fortran implementation).
