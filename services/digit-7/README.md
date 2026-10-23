# digit-7

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Gleam 1.19 on Erlang/OTP 28 (BEAM), `gen_tcp`, SQLite through `sqlight` (the `esqlite` NIF) |
| Database | SQLite (embedded), volume `digit-7-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 7, built in Gleam
to the reference behaviour of `digit-0` (ADR-0022, ADR-0029).

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7), the carry service
asks each digit it passes through, and the saga confirms the digits of the
operands (`resolveDigits`, step 6). Those callers arrive with P2.13 and
P3.3; until then the service runs but nobody calls it. If it is down, every
step that needs digit 7 waits and is retried by its caller: additions are
delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":7,"value":7}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":7,"next":8,"carry":false}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read. Outside the contract, the service's own
HTTP/1.1 server answers 400 for a malformed request, 413 for a request body
above 64 KiB and 431 for a request head above 8 KiB; these close the
connection. Connections are persistent (HTTP/1.1 keep-alive) and close after
10 s of silence. The full reference is [docs/API.md](docs/API.md); the
shared contract test is `make contract-digit-7`
([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-7.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 7, value 7, successor 8, no carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `src/digit7/store.gleam`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test
`value_comes_from_database_test` proves. The database does not grow; no
retention is needed.

## Code

The package follows Gleam's layout (`src/`, `test/`, `dev/`), which the
`gleam` tool requires (ADR-0029). No Erlang source is added: the Erlang
functions the service calls are typed `@external` declarations in Gleam.

| File | Responsibility |
| --- | --- |
| `src/digit7.gleam` | Configuration, start-up checks, the stop on SIGTERM |
| `src/digit7/server.gleam` | HTTP/1.1 server: a chain of acceptor processes, one process per connection, keep-alive, graceful stop |
| `src/digit7/http.gleam` | HTTP/1.1 framing: line reading with a byte budget, heads, bodies (Content-Length, chunked), reply formatting |
| `src/digit7/socket.gleam` | Typed bindings to `gen_tcp` and `inet` |
| `src/digit7/tracker.gleam` | Connection tracker (OTP actor): limit of 256, busy and idle connections, drain on stop |
| `src/digit7/api.gleam` | The contract as a function `(method, path) → Reply`, run by the contract process (OTP actor) that owns the database and the counters |
| `src/digit7/store.gleam` | SQLite through `sqlight`: open, migrate, read the row |
| `src/digit7/metrics.gleam` | `digit_requests_total`, `digit_build_info` |
| `src/digit7/log.gleam` | JSON log lines (`CLAUDE.md` 6.1), JSON escaping |
| `src/digit7/trace.gleam` | `traceparent` parsing for the logs |
| `src/digit7/signal.gleam` | SIGTERM as a message (a `gen_event` handler of `erl_signal_server` written in Gleam) |
| `test/` | gleeunit tests against the real migrations, the HTTP framing on prepared input and the server over TCP |
| `dev/doc_coverage.gleam` | Documentation coverage gate (parses the sources with `glance`) |
| `gleam.toml`, `manifest.toml` | Package manifest and the lock file of the Hex packages |

The runtime image is Alpine with a reduced Erlang/OTP (erts, kernel,
stdlib); `wget` (busybox) is available for manual checks inside the
container.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-7` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `7` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-7.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |
| `ERL_LIBS` | `/app/lib` | Set by the image: where the Erlang runtime finds the compiled packages |

## Running and testing

```sh
make build-digit-7         # image through Compose (root Makefile)
make test-digit-7          # gleeunit tests in the Dockerfile `test` stage
make lint-digit-7          # gleam format --check, gleam build --warnings-as-errors
make fmt-digit-7           # gleam format in place
make doc-coverage-digit-7  # dev/doc_coverage.gleam (100%) and gleam docs build
make api-docs-digit-7      # gleam docs HTML to build/api-docs/digit-7
make up && make contract-digit-7   # shared contract test against the container
make logs SVC=digit-7
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md)
(reference behaviour), [ADR-0029](../../docs/adr/0029-digit-7-gleam-on-gen-tcp.md)
(Gleam implementation).
