# digit-1

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | C++20 (g++ 14), cpp-httplib 0.26.0, nlohmann-json 3.11, SQLite 3.49 |
| Database | SQLite (embedded), volume `digit-1-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 1, built in C++
to the reference behaviour of `digit-0` (ADR-0022, ADR-0023).

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7), the carry service
asks each digit it passes through, and the saga confirms the digits of the
operands (`resolveDigits`, step 6). Those callers arrive with P2.13 and
P3.3; until then the service runs but nobody calls it. If it is down, every
step that needs digit 1 waits and is retried by its caller: additions are
delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":1,"value":1}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":1,"next":2,"carry":false}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read. The HTTP server adds two answers outside
the contract, also as problem details: 413 for a request body above 1 KiB
and 400 for a malformed request (including a method name that is not an
HTTP method). The full reference is
[docs/API.md](docs/API.md); the shared contract test is
`make contract-digit-1` ([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-1.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 1, value 1, successor 2, no carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `src/store.cpp`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test case
`answers come from the database` proves. The database does not grow;
no retention is needed.

## Code

| File | Responsibility |
| --- | --- |
| `src/main.cpp` | Configuration, start-up checks, cpp-httplib server (catch-all routes, error handler), SIGTERM |
| `src/api.cpp` | The contract as a function `(method, path) → Reply`; one mutex around the SQLite connection |
| `src/store.cpp` | SQLite (RAII): open, migrate, read the row |
| `src/metrics.cpp` | `digit_requests_total` (atomic counters), `digit_build_info` |
| `src/log.cpp` | JSON log lines (`CLAUDE.md` 6.1) with nlohmann-json |
| `src/trace.cpp` | `traceparent` parsing for the logs |
| `tests/test_digit.cpp` | doctest unit tests against the real migrations |

The server runs four worker threads with keep-alive (idle connections close
after 10 s) and TCP_NODELAY; requests share the one SQLite connection under
a mutex, which costs little at about 0.09 ms per request (docs/CAPACITY.md).

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-1` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `1` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-1.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |

## Running and testing

```sh
make build-digit-1         # image through Compose (root Makefile)
make test-digit-1          # unit tests in the Dockerfile `test` stage
make lint-digit-1          # clang-format check, clang-tidy, g++ -Werror
make fmt-digit-1           # clang-format in place
make doc-coverage-digit-1  # Doxygen, every definition documented (100%)
make api-docs-digit-1      # Doxygen HTML to build/api-docs/digit-1
make up && make contract-digit-1   # shared contract test against the container
make logs SVC=digit-1
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md)
(reference behaviour), [ADR-0023](../../docs/adr/0023-digit-1-in-cpp-with-cpp-httplib.md)
(C++ implementation).
