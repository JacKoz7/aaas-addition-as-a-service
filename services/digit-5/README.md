# digit-5

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Dart 3.13.4 (AOT executable), sqlite3 3.7.0 (FFI), SQLite 3.46 |
| Database | SQLite (embedded), volume `digit-5-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC: the digit contract is HTTP/JSON) |
| Version | 0.1.0 |

## Role

Authoritative source for the value and successor of digit 5, built in Dart
to the reference behaviour of `digit-0` (ADR-0022, ADR-0027).

In the addition flow (`CLAUDE.md` 3), the successor service asks the digit
service of the units digit for the next digit (step 7), the carry service
asks each digit it passes through, and the saga confirms the digits of the
operands (`resolveDigits`, step 6). Those callers arrive with P2.13 and
P3.3; until then the service runs but nobody calls it. If it is down, every
step that needs digit 5 waits and is retried by its caller: additions are
delayed, never wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /value` → `{"digit":5,"value":5}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /next` → `{"digit":5,"next":6,"carry":false}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /health` → `{"status":"ok","checks":{"database":"ok"}}` | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| HTTP | `GET /metrics` (`digit_requests_total`, `digit_build_info`) | in | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |

Errors are problem details: 404 unknown path, 405 with `Allow: GET`, 503
when the database cannot be read. Outside the contract, the service's own
HTTP/1.1 server answers 400 for a malformed request, 413 for a request body
above 64 KiB and 431 for a request head above 8 KiB; these close the
connection. Connections are persistent (HTTP/1.1 keep-alive) and close after
10 s of silence. The full reference is [docs/API.md](docs/API.md); the
shared contract test is `make contract-digit-5`
([tests/contract](../../tests/contract/README.md)).

## Database

SQLite (embedded) in `/data/digit-5.db`. The service never reads another
service's database.

| Table | Content |
| --- | --- |
| `digit` | Exactly one row: digit 5, value 5, successor 6, no carry ([`migrations/0001_digit.sql`](migrations/0001_digit.sql)) |
| `schema_migrations` | One row per applied migration file (created by the runner in `lib/src/store.dart`) |

Migrations are the files `migrations/NNNN_*.sql`, applied at start-up in
lexical order, each once, in one transaction with its record. `/value`,
`/next` and `/health` read the row on every request; nothing about the digit
is hard-coded (`CLAUDE.md` 4.4), which the unit test "answers from the
database, not from constants" proves. The database does not grow; no
retention is needed.

## Code

The service follows the Dart package layout (`bin/`, `lib/`, `test/`,
`tool/`), which `dart build`, `dart test` and `dart doc` expect
(ADR-0027).

| File | Responsibility |
| --- | --- |
| `bin/digit5.dart` | Configuration, start-up checks, SIGTERM and SIGINT |
| `lib/src/server.dart` | HTTP/1.1 server on `dart:io` sockets: one asynchronous task per connection, keep-alive, head and body limits, connection cap, graceful stop |
| `lib/src/api.dart` | The contract as a function `(method, path) → Reply` |
| `lib/src/store.dart` | SQLite (package sqlite3): open, migrate, read the row |
| `lib/src/metrics.dart` | `digit_requests_total`, `digit_build_info` |
| `lib/src/log.dart` | JSON log lines (`CLAUDE.md` 6.1), JSON escaping |
| `lib/src/trace.dart` | `traceparent` parsing for the logs |
| `lib/digit_service.dart` | The library that exports the modules above |
| `test/digit_test.dart` | package:test tests against the real migrations, including the HTTP transport |
| `tool/doc_coverage.dart` | Documentation coverage gate (a `///` comment on every declaration, through package:analyzer) |
| `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` | Dependencies (exact versions), lints |

The runtime image is `scratch` with the Dart runtime files (no shell): use
`/usr/local/bin/wget` (busybox) for manual checks inside the container.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `digit-5` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_DIGIT` | `5` | The digit the service represents; the database row must match it |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_DB_PATH` | `/data/digit-5.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per request), `info`, `warn` or `error` |

## Running and testing

```sh
make build-digit-5         # image through Compose (root Makefile)
make test-digit-5          # package:test tests in the Dockerfile `test` stage
make lint-digit-5          # dart format check, dart analyze --fatal-infos
make fmt-digit-5           # dart format in place
make doc-coverage-digit-5  # tool/doc_coverage.dart and dartdoc without warnings (100%)
make api-docs-digit-5      # dartdoc HTML to build/api-docs/digit-5
make up && make contract-digit-5   # shared contract test against the container
make logs SVC=digit-5
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0022](../../docs/adr/0022-digit-0-reference-implementation-in-c.md)
(reference behaviour), [ADR-0027](../../docs/adr/0027-digit-5-dart-own-http-server.md)
(Dart implementation).
