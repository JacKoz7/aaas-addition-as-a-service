# digit-9

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Racket 9.2 (Racket CS, Alpine's minimal distribution), Racket TCP ports and threads, SQLite through the foreign function interface (`ffi/unsafe`) |
| Database | SQLite (embedded), volume `digit-9-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 9, built in
Racket to the reference behaviour of `digit-0` (ADR-0022, ADR-0031). It is
the only digit service whose successor wraps: `GET /next` answers 0 with
`carry: true`.

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7); when the units
digit is 9, the carry this service reports makes the successor call the
carry service, which asks the digit services of the higher positions in
turn. The saga confirms the digits of the operands (`resolveDigits`, step
6). Those callers arrive with P2.13 and P3.3; until then the service runs
but nobody calls it. If it is down, every step that needs digit 9 waits
and is retried by its caller: additions are delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":9,"value":9}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":9,"next":0,"carry":true}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read. Outside the contract, the service's own
HTTP/1.1 server answers 400 for a malformed request, 413 for a request body
above 64 KiB and 431 for a request head above 8 KiB; these close the
connection. Connections are persistent (HTTP/1.1 keep-alive) and close after
10 s of silence. The full reference is [docs/API.md](docs/API.md); the
shared contract test is `make contract-digit-9`
([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-9.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 9, value 9, successor 0, carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `src/digit9/store.rkt`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test "the replies come from
the database on every request, not from code" in `tests/contract-test.rkt`
proves. The database does not grow; no retention is needed.

## Code

At runtime the service uses only Racket's base library; SQLite is reached
through the foreign function interface, because Racket's `db` library
doubles the memory of the process (ADR-0031).

| File | Responsibility |
| --- | --- |
| `src/digit9/main.rkt` | The entry point (`main` submodule) of the executable |
| `src/digit9/service.rkt` | Configuration, start-up checks, SIGTERM, SIGINT and SIGHUP (Racket breaks) |
| `src/digit9/server.rkt` | TCP server: an accept thread, one Racket thread and custodian per connection, connection cap, lingering close, graceful stop |
| `src/digit9/http.rkt` | HTTP/1.1 framing: buffered line reading with a byte budget, heads, bodies (Content-Length, chunked), keep-alive, reply formatting, the request loop |
| `src/digit9/api.rkt` | The contract as a function `(method, path) → reply` |
| `src/digit9/store.rkt` | SQLite: open, migrate, read the row |
| `src/digit9/sqlite.rkt` | The foreign-function bindings to the SQLite C library |
| `src/digit9/memory.rkt` | The memory guard: a major garbage collection when the runtime holds 12 MiB more memory |
| `src/digit9/metrics.rkt` | `digit_requests_total`, `digit_build_info` |
| `src/digit9/log.rkt` | JSON log lines (`CLAUDE.md` 6.1), JSON escaping |
| `src/digit9/trace.rkt` | `traceparent` parsing for the logs |
| `tests/` | rackunit tests against the real migrations: the contract and the database, the HTTP framing over string ports, the server over TCP, the configuration, and the examples of every doc comment |
| `tools/docs.rkt` | Reads the doc comments of a module (shared by the tools and the example tests) |
| `tools/doc-coverage.rkt` | Documentation coverage gate (100%, private definitions included) |
| `tools/api-docs.rkt` | Renders the API documentation with Scribble |

Every module-level definition has a `;;` doc comment with the fields of
`CLAUDE.md` 6.5.3. Its `Example:` lines starting with `>` are evaluated
inside the module by `tests/examples-test.rkt`, and the result is compared
with the lines that follow.

For manual checks inside the container, the runtime image has busybox
(`wget`, `sh`).

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-9` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `9` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-9.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |

## Running and testing

```sh
make build-digit-9         # image through Compose (root Makefile)
make test-digit-9          # raco test in the Dockerfile `test` stage
make lint-digit-9          # raco fmt check, line limit, compilation, raco review
make fmt-digit-9           # raco fmt in place
make doc-coverage-digit-9  # tools/doc-coverage.rkt (100%)
make api-docs-digit-9      # Scribble HTML to build/api-docs/digit-9
make up && make contract-digit-9   # shared contract test against the container
make logs SVC=digit-9
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md)
(reference behaviour), [ADR-0031](../../docs/adr/0031-digit-9-racket-on-tcp-ports.md)
(Racket implementation).
