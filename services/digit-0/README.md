# digit-0

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | C17 (GCC 14), libmicrohttpd 1.0.1, SQLite 3.49 |
| Database | SQLite (embedded), volume `digit-0-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 0, and the
reference implementation of the digit contract that the nine other digit
services follow (ADR-0022).

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7), the carry service
asks each digit it passes through, and the saga confirms the digits of the
operands (`resolveDigits`, step 6). Those callers arrive with P2.13 and
P3.3; until then the service runs but nobody calls it. If it is down, every
step that needs digit 0 waits and is retried by its caller: additions are
delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":0,"value":0}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":0,"next":1,"carry":false}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read. The full reference is
[docs/API.md](docs/API.md); the shared contract test is
`make contract-digit-0` ([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-0.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 0, value 0, successor 1, no carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `src/store.c`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test
`test_answers_come_from_the_database` proves. The database does not grow;
no retention is needed.

## Code

| File | Responsibility |
| --- | --- |
| `src/main.c` | Configuration, start-up checks, libmicrohttpd server, SIGTERM |
| `src/api.c` | The contract as a pure function `(method, path) → reply` |
| `src/store.c` | SQLite: open, migrate, read the row |
| `src/metrics.c` | `digit_requests_total`, `digit_build_info` |
| `src/log.c` | JSON log lines (`CLAUDE.md` 6.1), JSON escaping |
| `src/trace.c` | `traceparent` parsing for the logs |
| `tests/test_digit.c` | Unit tests against the real migrations |

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-0` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `0` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-0.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |

## Running and testing

```sh
make build-digit-0         # image through Compose (root Makefile)
make test-digit-0          # unit tests in the Dockerfile `test` stage
make lint-digit-0          # clang-format check, clang-tidy, gcc -Werror
make fmt-digit-0           # clang-format in place
make doc-coverage-digit-0  # Doxygen, every definition documented (100%)
make api-docs-digit-0      # Doxygen HTML to build/api-docs/digit-0
make up && make contract-digit-0   # shared contract test against the container
make logs SVC=digit-0
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md).
