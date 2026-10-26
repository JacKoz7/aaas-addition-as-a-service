# carry

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Elixir 1.20 on Erlang/OTP 28: gRPC server `grpc_server` 1.0 (Cowboy), Kafka client brod 4.7, HTTP client `:httpc`, ADR-0032 |
| Database | Mnesia (embedded in the BEAM node), volume `carry-data` |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (`/health`, `/metrics`), 9090 gRPC (`aaas.carry.v1.CarryService`) |
| Version | 0.1.0 |

## Role

Propagates a carry to the higher digit positions of a number. Step 7 of
the request flow (`CLAUDE.md` 3): the successor service increments the
units digit by asking its digit service; when that digit was 9, `digit-9`
answers 0 with `carry: true`, and the successor calls `Propagate` with the
digits of the number (units first) and position 1. The carry service asks
the digit service of each visited digit for its successor and continues
upwards while the answers carry; past the highest digit it appends the
successor of 0, asked from `digit-0`. It never adds natively (`CLAUDE.md`
1, rule 5).

Every call is recorded in Mnesia and announced as
`aaas.carry.propagated.v1`. The successor calls the service from P2.13b;
until then the service runs and answers, but nobody calls it. If it is
down, every successor call of a number ending in 9 fails with
`UNAVAILABLE` and is retried by its caller: additions are delayed, never
wrong.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| gRPC | `aaas.carry.v1.CarryService/Propagate` | in | [`carry.proto`](../../contracts/proto/aaas/carry/v1/carry.proto) |
| HTTP | `GET /value`, `GET /next` of `digit-0` … `digit-9` | out | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| Event | `aaas.carry.propagated.v1` | out (key `taskId`) | [schema](../../contracts/events/aaas.carry.propagated.v1.schema.json) |
| HTTP | `GET /health`, `GET /metrics` | in | [docs/API.md](docs/API.md) |

Only `GET /next` of the digit services is used. The `traceparent` metadata
of a call is continued in the log lines, in the requests to the digit
services and in the event. Details: [docs/API.md](docs/API.md).

## Processing of one call

1. Validate the request: 1 to 6 digits in `0..9`, a position in
   `0..length(digits)`, a lowercase UUIDv7 `task_id` (`INVALID_ARGUMENT`
   otherwise).
2. Look up `{task_id, digits, position}` in the propagation log. A
   recorded call (a retry) republishes its stored event and answers its
   stored digits.
3. Otherwise ask `GET /next` of the digit service of each visited digit:
   250 ms per attempt, three attempts with 50 ms and 100 ms pauses plus
   jitter, all within the call's budget (the caller's deadline, at most
   1.8 s).
4. Build the event and record the call in one Mnesia transaction; when a
   concurrent attempt of the same call recorded first, its record wins.
5. Publish the recorded event and wait for the broker's acknowledgement
   (all in-sync replicas, 1 s).
6. Answer the digits after the carry.

A failure of a digit service, Mnesia or the broker answers `UNAVAILABLE`;
the caller retries the same call, which is safe (steps 2 and 4).

## Database

Mnesia, the database of Erlang/OTP, runs inside the service's BEAM node
(not distributed, node `nonode@nohost`) with its schema in
`/data/mnesia`. The service never reads another service's database.

| Table | Storage | Content |
| --- | --- | --- |
| `carry_propagations` | `disc_only_copies` (dets file, no copy in memory) | One record per call, key `{task_id, digits, position}`: `task_id`, `digits`, `position`, `result`, `event_id`, `event` (the published JSON), `propagated_at`, `trace_id` ([`migrations/0001_propagations.json`](migrations/0001_propagations.json)) |
| `carry_migrations` | `disc_copies` | One record per applied migration file (created by the runner in `src/carry/store.ex`) |

Migrations are the files `migrations/NNNN_*.json`, applied at start-up in
name order, each once. A migration lists operations; `createTable` stores
the documentation of the table and of every attribute as the table's user
property `aaas_documentation`, the Mnesia counterpart of `COMMENT ON`.
Records older than `AAAS_RETENTION_HOURS` are deleted every hour
(`src/carry/retention.ex`).

## Code

| File | Responsibility |
| --- | --- |
| `src/carry/application.ex` | Start-up (configuration, logger, Mnesia, Kafka client, supervision tree) and graceful shutdown |
| `src/carry/config.ex` | Environment variables, checked at start-up |
| `src/carry/grpc/server.ex`, `endpoint.ex` | The gRPC service and its endpoint on port 9090 |
| `src/carry/propagation.ex` | One `Propagate` call end to end |
| `src/carry/core.ex` | Validation and the propagation through the digits, without I/O |
| `src/carry/digits.ex` | HTTP client of the digit services with timeouts and retries |
| `src/carry/store.ex` | Mnesia: schema, migrations, propagation log, retention query |
| `src/carry/publisher.ex` | Kafka producer (brod) |
| `src/carry/event.ex` | The event `aaas.carry.propagated.v1` |
| `src/carry/http.ex` | `GET /health`, `GET /metrics` (Cowboy) |
| `src/carry/metrics.ex` | The Prometheus metrics |
| `src/carry/retention.ex` | The hourly retention job |
| `src/carry/drain.ex` | Calls in progress and the graceful stop |
| `src/carry/log.ex` | JSON log lines (`CLAUDE.md` 6.1) |
| `src/carry/trace.ex`, `uuid.ex` | `traceparent` and UUIDv7 |
| `gen/` | Not in Git: `contracts/gen/elixir/aaas/carry`, copied by the Dockerfile from the `contracts` build context (ADR-0020) |
| `tests/` | ExUnit tests: doctests, the pure modules, and the service with real Mnesia, fake digit services and a fake publisher |
| `tools/doc_coverage.exs` | Documentation coverage gate (private definitions included) |

Every module and public function has `@moduledoc`/`@doc` with the fields
of `CLAUDE.md` 6.5.3 and a `@spec`; every private function, private type
and constant has a `#` comment with those fields. The `iex>` examples run
as doctests.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `carry` | Service name in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; any other value stops the start |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_GRPC_PORT` | `9090` | gRPC port |
| `AAAS_KAFKA_BROKERS` | `redpanda:9092` | Kafka bootstrap servers, `host:port[,host:port]` |
| `AAAS_DIGIT_URL_TEMPLATE` | `http://digit-{digit}:8080` | Base URL of the digit services; `{digit}` is replaced by 0 … 9 |
| `AAAS_DB_DIR` | `/data/mnesia` | Mnesia directory |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Directory of the migration files |
| `AAAS_RETENTION_HOURS` | `24` | Age after which propagation records are deleted, 1 … 8760 |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per call), `info`, `warn` or `error` |

The image also sets `RELEASE_DISTRIBUTION=none`, `RELEASE_MODE=interactive`
and the emulator flags of `ELIXIR_ERL_OPTIONS`; the Dockerfile explains
each.

## Running and testing

```sh
make build-carry          # image through Compose (root Makefile)
make test-carry           # mix test and the event schema check in the `test` stage
make lint-carry           # mix format check, Credo strict, warnings as errors
make fmt-carry            # mix format in place
make doc-coverage-carry   # tools/doc_coverage.exs and Doctor (100%)
make api-docs-carry       # ExDoc HTML to build/api-docs/carry
make up
make logs SVC=carry
```

A call by hand, from a container on the `services` network:

```sh
docker run --rm --network aaas-services -v "$PWD/contracts/proto":/p -w /p \
  bufbuild/buf:1.74.0 curl --schema . --protocol grpc --http2-prior-knowledge \
  --data '{"digits":[0,9,9],"position":1,"taskId":"<uuidv7>"}' \
  http://carry:9090/aaas.carry.v1.CarryService/Propagate
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
Decisions: [ADR-0020](../../docs/adr/0020-grpc-contracts-and-code-generation.md)
(gRPC contracts), [ADR-0032](../../docs/adr/0032-carry-elixir-mnesia-grpc.md)
(this service).
