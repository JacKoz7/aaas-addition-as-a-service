# digit-4

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Lua 5.4.7, cqueues 20200726, lsqlite3 0.9.6, luaposix 36.3, SQLite 3.49 |
| Database | SQLite (embedded), volume `digit-4-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 4, built in Lua
to the reference behaviour of `digit-0` (ADR-0022, ADR-0026).

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7), the carry service
asks each digit it passes through, and the saga confirms the digits of the
operands (`resolveDigits`, step 6). Those callers arrive with P2.13 and
P3.3; until then the service runs but nobody calls it. If it is down, every
step that needs digit 4 waits and is retried by its caller: additions are
delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":4,"value":4}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":4,"next":5,"carry":false}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read. Outside the contract, the service's own
HTTP/1.1 server answers 400 for a malformed request, 413 for a request body
above 64 KiB and 431 for a request head above 8 KiB; these close the
connection. Connections are persistent (HTTP/1.1 keep-alive) and close after
10 s of silence. The full reference is [docs/API.md](docs/API.md); the
shared contract test is `make contract-digit-4`
([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-4.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 4, value 4, successor 5, no carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `src/digit/store.lua`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test "answers from the
database, not from constants" proves. The database does not grow; no
retention is needed.

## Code

| File | Responsibility |
| --- | --- |
| `src/main.lua` | Configuration, start-up checks, the cqueues controller, SIGTERM and SIGINT through a signalfd |
| `src/digit/http.lua` | HTTP/1.1 server: one coroutine per connection, keep-alive, head and body limits, connection cap, graceful stop |
| `src/digit/api.lua` | The contract as a function `(method, path) → reply` |
| `src/digit/store.lua` | SQLite (lsqlite3): open, migrate, read the row |
| `src/digit/metrics.lua` | `digit_requests_total`, `digit_build_info` |
| `src/digit/log.lua` | JSON log lines (`CLAUDE.md` 6.1), JSON escaping |
| `src/digit/trace.lua` | `traceparent` parsing for the logs |
| `tests/digit_spec.lua` | busted tests against the real migrations, including the HTTP transport through a connection double |
| `tools/doc-coverage.lua` | Documentation coverage gate (an LDoc comment above every definition) |
| `.busted`, `.luacheckrc`, `stylua.toml`, `config.ld` | Settings of busted, luacheck, StyLua and LDoc |

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-4` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `4` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-4.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |
| `LUA_PATH` | `/app/src/?.lua;;` (image) | Module path of the interpreter; set in the Dockerfile |

## Running and testing

```sh
make build-digit-4         # image through Compose (root Makefile)
make test-digit-4          # busted tests in the Dockerfile `test` stage
make lint-digit-4          # StyLua check, luacheck, luac -p
make fmt-digit-4           # StyLua in place
make doc-coverage-digit-4  # tools/doc-coverage.lua and LDoc with warnings as errors (100%)
make api-docs-digit-4      # LDoc HTML to build/api-docs/digit-4
make up && make contract-digit-4   # shared contract test against the container
make logs SVC=digit-4
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md)
(reference behaviour), [ADR-0026](../../docs/adr/0026-digit-4-lua-http-server-on-cqueues.md)
(Lua implementation).
