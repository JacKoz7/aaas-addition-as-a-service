# ADR-0033: successor — n + 1 through the digit services and carry, gRPC with grapesy

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-26 |
| Deciders | Arithmetic Excellence Center (AEC), Transaction Integrity Office (TIO) |
| Step | P2.13b |
| Amends | ADR-0016 (the native successor and the HTTP-only interface) |

## Context

Until now `successor` (Haskell, ADR-0016) computed `n + 1` natively,
marked `TEMPORARY(P2.13)`, and served only the HTTP/JSON form
`POST /v1/next`. P2.13 of `CLAUDE.md` 9.3, split into P2.13a (`carry`,
ADR-0032) and P2.13b (this ADR), replaces that with the computation of
`CLAUDE.md` 3, step 7: the digit service of the units digit answers its
successor (`GET /next`, `CLAUDE.md` 4.4), and on a carry the carry service
(`aaas.carry.v1.CarryService/Propagate`) carries the one into the higher
digits. The service also serves the gRPC method `Next` of `CLAUDE.md` 4.3
on port 9090; `POST /v1/next` stays for the ledger until P3.3 (ADR-0020).

Open questions: the Haskell gRPC library, how the generated messages of
`contracts/gen/haskell` are compiled, how the digits of `n` are obtained
without native arithmetic, what a retried call does, the timeouts of the
new calls, how the trace crosses gRPC, and how the process stops.

## Decision

- **gRPC library: grapesy 1.2.1** (Well-Typed; a native Haskell
  implementation over `http2` 5.4.6, with proto-lens messages) for the
  server and the client. The alternatives were rejected: `gRPC-haskell`
  binds the C core of gRPC (an extra C library and an unmaintained
  binding), `mu-haskell` is unmaintained. grapesy needs `http2 == 5.4.6`;
  warp 3.4.16 accepts it, so the HTTP server is unchanged. The `snappy`
  flag of `grpc-spec` is off (`cabal.project`): messages are a few bytes
  and are sent uncompressed, and no snappy C library is needed. The build
  of `proto-lens-protobuf-types`, a dependency of grapesy, runs `protoc`;
  Debian's `protobuf-compiler` and `libprotobuf-dev` (3.21.12, pinned) are
  installed in the toolchain stage only.
- **Generated messages.** The modules of `contracts/gen/haskell` for the
  two services involved (`Proto.Aaas.Successor.V1.*`,
  `Proto.Aaas.Carry.V1.*`, ADR-0020) are copied by the Dockerfile from the
  named build context `contracts` into `gen/` and compiled as the internal
  library `successor:proto` with warnings off. They are not formatted,
  linted or counted by the Haddock coverage gate; their documentation is
  the `.proto` file. The type family instances that grapesy needs (request
  and response metadata of each method) live in `Successor.Rpc`.
- **Digits as decimal text.** `toDigits` reads the digits of `n` from its
  decimal text (`show`), least significant first, and `fromDigits` writes
  a list of digits back as text and reads it (`read`). No arithmetic is
  applied to `n`: the only arithmetic fact is the answer of the digit
  service, and the carry service computes the higher digits. Native `+` is
  left in helper code only (retry counters, backoff delays, a counter of
  calls in progress), as `CLAUDE.md` 1, rule 5 allows.
- **One digit call, at most one carry call.** `successorVia` asks the
  service of the units digit. Without a carry, the units digit is
  replaced. With a carry (the units digit was 9), the units digit becomes
  0 and `Propagate(digits, 1, taskId)` returns the result. A test checks
  the whole domain, `0 .. 199 997`, against the digit table and a carry
  oracle.
- **Retries are computed again.** A retried call (the same `taskId` and
  `n`) asks the digit service and the carry service again (`carry` answers
  it from its own log, ADR-0032); the stored result must equal the new one
  before the stored event is published again (unchanged `eventId`). This
  keeps the protection of ADR-0016 against a tampered call log; answering
  a retry from the log without recomputing it was rejected for that
  reason.
- **Timeouts and retries** (`CLAUDE.md` 6.1). A digit call: 250 ms per
  attempt, three attempts with 50 ms and 100 ms backoff and ±50% jitter (as
  the CouchDB calls); a reply outside the contract (another digit, a
  successor outside 0..9) counts as a failed attempt. A carry call: a 2 s
  deadline for the whole call (the carry service's own budget is 1.8 s),
  up to three attempts when the status is `UNAVAILABLE` or the connection
  was lost; other statuses are final. One HTTP/2 connection to `carry` is
  shared by all calls (`TCP_NODELAY` on, ADR-0032); grapesy connects again
  every 100–200 ms while it is down, and a call made meanwhile waits up to
  its deadline. A failure answers 503 (HTTP) or `UNAVAILABLE` (gRPC) and
  names the dependency in the log and in
  `successor_dependency_failures_total{dependency}`.
- **`/health` keeps its two checks** (`database`, `broker`). An outage of a
  digit service or of `carry` fails the calls that need it, not the
  health of the successor, so that one failed dependency does not mark a
  second container unhealthy; the dependency has its own health check.
- **`task_id` must be a lowercase UUIDv7** on both interfaces, as the
  contract states and as `carry` requires. `POST /v1/next` accepted any
  UUID version before; the ledger has always sent UUIDv7.
- **Trace.** The W3C `traceparent` travels as gRPC custom metadata (an
  ASCII entry named `traceparent`, as the Elixir carry service reads it),
  not as grapesy's binary `grpc-trace-bin`. The serving span is passed on
  in the `traceparent` of every digit and carry call.
- **One handling, two interfaces.** `Successor.Api.serveCall` (serving
  span, call, metrics, log lines) is used by `POST /v1/next` and by the
  gRPC handler, so both interfaces count and log alike. Statuses of `Next`:
  `INVALID_ARGUMENT` for a malformed `task_id`, `OUT_OF_RANGE` for
  `n > 199 997`, `UNAVAILABLE` for a failed dependency. An exception that
  escapes a handler is logged as one JSON warn line (grapesy's default
  prints it in plain text on stderr) and is answered as `internal error`.
- **Shutdown.** SIGTERM stops warp from accepting connections and sets a
  drain flag: new gRPC calls are answered `UNAVAILABLE`, and the calls in
  progress (a counter) get up to 8 s; the 9 s watchdog of ADR-0016 stays.

## Consequences

- Every successor step costs one digit call, and one carry call for a
  number ending in 9, instead of a native `+`; the measured latency and
  memory are in `services/successor/docs/CAPACITY.md` and `SLO.md`.
- The successor depends on eleven more services; Compose starts it after
  `carry` and the ten digit services are healthy.
- The image build needs the `contracts` build context
  (`additional_contexts` in Compose, `--build-context` in the component
  Makefile), like `carry`.
- The toolchain stage compiles grapesy and its dependencies (lens, tls,
  http2), about 50 more packages than before; `cabal.project.freeze` pins
  194 packages.
- The saga (P3.3) can call `Next` over gRPC; `POST /v1/next` and its
  `TEMPORARY(P3.3)` marker go with the ledger's loop in that step.
