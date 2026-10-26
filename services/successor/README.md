# successor

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Haskell (GHC 9.10; warp for HTTP, grapesy for gRPC; ADR-0016, ADR-0033) |
| Database | CouchDB 3.5.1 (`successor-db`, volume `successor-data`) |
| Compose profile | `services` |
| Networks | `services`, `data` |
| Ports (container) | 8080 HTTP, 9090 gRPC |
| Version | 0.2.0 |

## Role

Computes n+1 through the digit services and carry.

Step 7 of the request flow (`CLAUDE.md` 3): an addition `a + b` is `b`
successor calls, made by the ledger until P3.3 and by the saga afterwards.
The successor never adds natively: it asks the digit service of the units
digit of `n` for the next digit (`GET /next`, `CLAUDE.md` 4.4) and, when
that digit is 9 and reports a carry, asks `carry`
(`aaas.carry.v1.CarryService/Propagate`) to carry the one into the higher
digits. The digits of `n` are read from, and the result written as,
decimal text (ADR-0033). Every call is logged in CouchDB and announced as
`aaas.successor.called.v1`.

It serves the gRPC method `Next` of `CLAUDE.md` 4.3
(`contracts/proto/aaas/successor/v1/`) on port 9090, and the same call as
HTTP/JSON `POST /v1/next` for the ledger until P3.3 (`TEMPORARY(P3.3)`,
ADR-0020).

If the successor, a digit service or `carry` is down, additions stop
counting until it is back: the call fails with 503 or `UNAVAILABLE`, the
caller retries it, and no step is lost.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| gRPC | `aaas.successor.v1.SuccessorService/Next` | in (port 9090) | [`successor.proto`](../../contracts/proto/aaas/successor/v1/successor.proto); statuses `INVALID_ARGUMENT`, `OUT_OF_RANGE`, `UNAVAILABLE` |
| HTTP | `POST /v1/next` | in | `{ "n": <0..199997>, "taskId": <uuidv7> }` → `200 { "n": n + 1 }`; problems 400, 413, 422, 503 |
| HTTP | `GET /next` of `digit-0` … `digit-9` | out | [`contracts/http/digit.yaml`](../../contracts/http/digit.yaml) |
| gRPC | `aaas.carry.v1.CarryService/Propagate` | out (`carry:9090`) | [`carry.proto`](../../contracts/proto/aaas/carry/v1/carry.proto) |
| HTTP | `GET /health` | in | `{ "status", "checks": { "database", "broker" } }`, 503 on a failed check |
| HTTP | `GET /metrics` | in | Prometheus text format, metrics prefixed `successor_` |
| Event | `aaas.successor.called.v1` | out (key `taskId`) | [schema](../../contracts/events/aaas.successor.called.v1.schema.json) |

A `traceparent` header (HTTP) or metadata entry (gRPC) is continued in the
log lines, the event, and the calls to the digit services and `carry`.
Details: [docs/API.md](docs/API.md).

## Processing of one call

1. Validate the request; check `0 <= n <= 199997` (422 or `OUT_OF_RANGE`
   otherwise) and that `taskId` is a lowercase UUIDv7.
2. Ask `digit-<u>` for the successor of the units digit `u`. Without a
   carry, replace the units digit. With a carry, replace it (with 0) and
   ask `carry` to add the one at position 1; its digits are the result.
3. Write the call log document `<taskId>:<n>` with the result and the
   serialized event. If it already exists (a retried call), read it; its
   result must equal the one just computed (503 otherwise).
4. Publish the event (the stored one for a retry) and wait for the
   broker's acknowledgement.
5. Answer `n + 1`.

A failure of a digit service (three attempts of 250 ms), `carry` (2 s
deadline, up to three attempts on `UNAVAILABLE`), CouchDB (three attempts
of 250 ms) or Kafka (1 s message timeout) answers 503 or `UNAVAILABLE`; the
caller retries the same call, which is safe: the retry is computed again
(`carry` answers it from its own log) and publishes the stored event
(steps 3 and 4).

## Database

CouchDB 3.5.1, single node, built from [`couchdb/Dockerfile`](couchdb/Dockerfile)
with [`couchdb/10-aaas.ini`](couchdb/10-aaas.ini). The service never reads
another service's database. Migrations are JSON files in `migrations/`
(idempotent `createDatabase` and `putDocument` operations), applied at
startup in name order and recorded in the database `successor_migrations`.

| Database | Content |
| --- | --- |
| `successor_calls` | One document per call, `_id` `<taskId>:<n>`: `taskId`, `n`, `result`, `eventId`, `event` (the published JSON), `calledAt`, `traceId`; view `_design/call_log/_view/by_task` (key `[taskId, n]`); field documentation in `_design/call_log.aaas_documentation` |
| `successor_migrations` | One document per applied migration: `appliedAt`, `description` |

There is no retention job yet (R-014).

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `successor` | Service name used in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` until P5.2; `platform` is refused |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_GRPC_PORT` | `9090` | gRPC port (must differ from the HTTP port) |
| `AAAS_DIGIT_URL_TEMPLATE` | `http://digit-{digit}:8080` | Base URL of each digit service; `{digit}` is replaced by the digit |
| `AAAS_CARRY_ADDR` | `carry:9090` | `host:port` of the carry gRPC server |
| `AAAS_KAFKA_BROKERS` | `redpanda:9092` | Kafka bootstrap servers |
| `AAAS_DB_URL` | `http://successor-db:5984` | CouchDB base URL |
| `AAAS_DB_USER` | `successor` | CouchDB user |
| `SUCCESSOR_DB_PASSWORD` | (required) | CouchDB password (moves to OpenBao in P5.3) |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per call), `info`, `warn`, `error`, `fatal` |
| `AAAS_KAFKA_LOG_LEVEL` | `4` | librdkafka log level (0–7); its lines are written as JSON |

## Running and testing

```sh
make build-successor   # image through Compose (root Makefile)
make test-successor    # hspec, doctests, contract test, then CouchDB specs
make lint-successor    # ormolu check, hlint, -Werror build
make fmt-successor     # format sources in place with ormolu
make doc-coverage-successor  # Haddock coverage, private definitions included
make api-docs-successor      # Haddock HTML to build/api-docs/successor
make logs SVC=successor
```

`make test-successor` builds the `test` stage (38 hspec examples, 47
doctests of the documentation, and the JSON Schema check of every event
the tests published), then starts a throw-away `successor-db` container on
a private network and runs the 2 CouchDB specs against it. The digit
client, the carry client and the gRPC server are tested over real sockets
against in-process fakes (warp and grapesy on ephemeral ports).

The image build copies the generated gRPC messages from
`contracts/gen/haskell` (the `contracts` build context, ADR-0020); a call
of the running service:

```sh
docker run --rm --network aaas-services -v "$PWD/contracts/proto:/proto:ro" \
  bufbuild/buf:1.74.0 curl --schema /proto --protocol grpc --http2-prior-knowledge \
  -d '{"n":199,"taskId":"<uuidv7>"}' \
  http://successor:9090/aaas.successor.v1.SuccessorService/Next
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
