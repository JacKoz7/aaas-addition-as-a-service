# digit-3

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Free Pascal 3.2.2 (objfpc), fcl-web `TFPHttpServer`, SQLite 3.46 |
| Database | SQLite (embedded), volume `digit-3-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 3, built in Free
Pascal to the reference behaviour of `digit-0` (ADR-0022, ADR-0025).

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7), the carry service
asks each digit it passes through, and the saga confirms the digits of the
operands (`resolveDigits`, step 6). Those callers arrive with P2.13 and
P3.3; until then the service runs but nobody calls it. If it is down, every
step that needs digit 3 waits and is retried by its caller: additions are
delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":3,"value":3}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":3,"next":4,"carry":false}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read, and 413 for a request body above 64 KiB.
Every answer closes the connection (`Connection: close`). The full reference is
[docs/API.md](docs/API.md); the shared contract test is
`make contract-digit-3` ([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-3.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 3, value 3, successor 4, no carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `src/DigitStore.pas`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test
`TestAnswersComeFromTheDatabase` proves. The database does not grow;
no retention is needed.

## Code

| File | Responsibility |
| --- | --- |
| `src/digit3.lpr` | Program: `cthreads`, then `RunService` |
| `src/DigitService.pas` | Configuration, start-up checks, `TFPHttpServer` (one thread per connection, read timeout, body cap), SIGTERM |
| `src/DigitApi.pas` | The contract as a function `(method, path) → TReply`; a lock around the SQLite connection |
| `src/DigitStore.pas` | SQLite (`sqlite3` unit): open, migrate, read the row |
| `src/DigitMetrics.pas` | `digit_requests_total` (interlocked counters), `digit_build_info` |
| `src/DigitLog.pas` | JSON log lines (`CLAUDE.md` 6.1), JSON escaping |
| `src/DigitTrace.pas` | `traceparent` parsing for the logs |
| `tests/TestDigit.pas`, `tests/testrunner.lpr` | fpcunit tests against the real migrations and their runner |
| `tools/implementation-doc-check.awk` | Documentation check of the implementation sections |
| `pasfmt.toml` | Formatter settings |

The runtime image is distroless (no shell): use `/usr/local/bin/wget`
(busybox) for manual checks inside the container.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-3` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `3` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-3.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |

## Running and testing

```sh
make build-digit-3         # image through Compose (root Makefile)
make test-digit-3          # unit tests in the Dockerfile `test` stage
make lint-digit-3          # pasfmt check, fpc (warnings, notes, hints as errors)
make fmt-digit-3           # pasfmt in place
make doc-coverage-digit-3  # PasDoc (simplexml) and the implementation check (100%)
make api-docs-digit-3      # PasDoc HTML to build/api-docs/digit-3
make up && make contract-digit-3   # shared contract test against the container
make logs SVC=digit-3
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md)
(reference behaviour), [ADR-0025](../../docs/adr/0025-digit-3-free-pascal-fcl-web-on-debian.md)
(Free Pascal implementation).
