# digit-8

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | D (LDC 1.42), Phobos `std.socket` and `core.thread`, SQLite through Phobos's `etc.c.sqlite3` binding |
| Database | SQLite (embedded), volume `digit-8-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 8, built in D to
the reference behaviour of `digit-0` (ADR-0022, ADR-0030).

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7), the carry service
asks each digit it passes through, and the saga confirms the digits of the
operands (`resolveDigits`, step 6). Those callers arrive with P2.13 and
P3.3; until then the service runs but nobody calls it. If it is down, every
step that needs digit 8 waits and is retried by its caller: additions are
delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":8,"value":8}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":8,"next":9,"carry":false}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read. Outside the contract, the service's own
HTTP/1.1 server answers 400 for a malformed request, 413 for a request body
above 64 KiB and 431 for a request head above 8 KiB; these close the
connection. Connections are persistent (HTTP/1.1 keep-alive) and close after
10 s of silence. The full reference is [docs/API.md](docs/API.md); the
shared contract test is `make contract-digit-8`
([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-8.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 8, value 8, successor 9, no carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `src/digit8/store.d`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test "the replies come from
the database on every request" in `tests/digit8_tests/contract_test.d`
proves. The database does not grow; no retention is needed.

## Code

The dub package has no dependencies (ADR-0030): Phobos supplies the
sockets, the threads and the SQLite binding.

| File | Responsibility |
| --- | --- |
| `src/digit8/app.d` | `main` only (`dub test` leaves the main source file out of the test build) |
| `src/digit8/service.d` | Configuration, start-up checks, SIGTERM and SIGINT (`sigwait`) |
| `src/digit8/server.d` | TCP server: an accept thread, one thread per connection, connection cap, lingering close, joining of ended threads, graceful stop |
| `src/digit8/http.d` | HTTP/1.1 framing: line reading with a byte budget, heads, bodies (Content-Length, chunked), keep-alive, reply formatting, the request loop |
| `src/digit8/api.d` | The contract as a function `(method, path) → Reply` |
| `src/digit8/store.d` | SQLite: open, migrate, read the row |
| `src/digit8/metrics.d` | `digit_requests_total`, `digit_build_info` |
| `src/digit8/log.d` | JSON log lines (`CLAUDE.md` 6.1), JSON escaping |
| `src/digit8/trace.d` | `traceparent` parsing for the logs |
| `tests/digit8_tests/` | Unit tests against the real migrations: the contract and the database, the HTTP framing through a connection double, the server over TCP, the configuration |
| `tools/doc_coverage.d` | Documentation coverage gate on the compiler's JSON description |
| `dub.sdl` | Package recipe: the executable, the unit-test build, the static `production` build type |
| `dscanner.ini`, `.editorconfig` | D-Scanner checks; dfmt settings |

The `unittest` blocks directly after a declaration in `src/` are ddoc
"documented unit tests": they are the declaration's example in the
generated documentation and run with the other tests.

The runtime image is `scratch` (no shell): use `/usr/local/bin/wget`
(busybox) for manual checks inside the container.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-8` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `8` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-8.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |

## Running and testing

```sh
make build-digit-8         # image through Compose (root Makefile)
make test-digit-8          # dub test in the Dockerfile `test` stage
make lint-digit-8          # dfmt check, D-Scanner, builds with warnings and deprecations as errors
make fmt-digit-8           # dfmt in place
make doc-coverage-digit-8  # tools/doc_coverage.d and ddoc with warnings as errors (100%)
make api-docs-digit-8      # ddoc HTML to build/api-docs/digit-8
make up && make contract-digit-8   # shared contract test against the container
make logs SVC=digit-8
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md)
(reference behaviour), [ADR-0030](../../docs/adr/0030-digit-8-d-with-phobos.md)
(D implementation).
