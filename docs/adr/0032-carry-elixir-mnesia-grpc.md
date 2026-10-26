# ADR-0032: carry — Elixir gRPC server on Cowboy, Mnesia propagation log, brod

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-26 |
| Deciders | Arithmetic Excellence Center (AEC), Platform Enablement Guild (PEG) |
| Step | P2.13a |

## Context

`CLAUDE.md` 2 assigns `carry` to Elixir with Mnesia. It serves the gRPC
method `CarryService.Propagate` of `CLAUDE.md` 4.3
(`contracts/proto/aaas/carry/v1/carry.proto`), asks the digit services for
the successor of every visited digit (`CLAUDE.md` 3, step 7) and is the
producer of `aaas.carry.propagated.v1` (4.2), which had no schema yet. It
is the first Elixir service and the first gRPC server of AaaS, so the
generated Elixir code of P2.1 is compiled for the first time.

P2.13 of `CLAUDE.md` 9.3 also rewrites `successor` (Haskell) to call the
digit services and `carry` and to serve gRPC. Two new gRPC servers in two
runtimes do not fit one session (`CLAUDE.md` 8, rule 11), so the step is
split: P2.13a (`carry`, this ADR) and P2.13b (`successor`).

Open questions: the gRPC server, the HTTP endpoint next to it, what makes a
retried call safe, how Mnesia is stored, migrated and bounded, how the
event is published, how the BEAM fits 128 MiB at 0.5 CPU, and how the
documentation rules of 6.5 map to Elixir.

## Decision

- **Toolchain.** Elixir 1.20.4 on Erlang/OTP 28.5
  (`elixir:1.20.4-otp-28-alpine`, Alpine 3.24, multi-arch), Hex 2.6.0,
  the rebar3 version pinned by Mix. Every Hex package is pinned to one
  version in `mix.exs` and by checksum in `mix.lock`.
- **gRPC.** `grpc_server` 1.0.5 (elixir-grpc, on Cowboy 2.20 and ranch
  2.3) serves the generated `Aaas.Carry.V1.CarryService.Service`. The
  generated file also defines the client stub, so `grpc` 1.0.5 is a
  compile-time dependency; the tests use it as the client, with Mint 1.11
  (gun 2.4, its other adapter, has an open advisory). The generated code is
  copied from the `contracts` build context into `gen/` (not in Git).
  Failures map to the statuses of the contract: `INVALID_ARGUMENT`,
  `UNAVAILABLE` (the caller retries) and `INTERNAL` (a digit service
  answered outside its contract). The gRPC server does not log
  `GRPC.RPCError`s (an exception log filter): they are answers, logged by
  the service as one JSON warning line.
- **HTTP 8080.** A plain Cowboy listener for `GET /health` and
  `GET /metrics` (Cowboy is already a dependency of the gRPC server);
  problem details for other paths and methods; 256 connections and 10 s
  idle timeout per listener, gRPC bodies up to 4 KiB.
- **Digit services through `:httpc`.** The HTTP client of OTP's inets with
  a persistent-connection profile (connections kept 5 s, below the 10 s
  idle timeout of the digit services); 250 ms per attempt, three attempts
  with 50 ms and 100 ms pauses and up to 25 ms of jitter; the call budget
  is the caller's deadline, capped at 1.8 s as in `successor` (ADR-0016).
  Every answer is checked: the digit asked, a successor in 0..9, a boolean
  carry. The new highest digit is the successor of 0 asked from `digit-0`,
  so the service never adds a digit itself (`CLAUDE.md` 1, rule 5).
- **Natural key of a call.** Within one addition the successor asks for
  the carry of each number ending in 9 once, so
  `{task_id, digits, position}` identifies a call. A recorded call is
  answered from the log and its stored event is published again (same
  `eventId`); the record is written in one Mnesia transaction that keeps
  the first record of a key, so concurrent attempts store one. The answer
  comes after the record and the broker's acknowledgement.
- **Mnesia.** A non-distributed node (`RELEASE_DISTRIBUTION=none`, node
  `nonode@nohost`): a disc schema is bound to the node name, and a
  distributed name would contain the container's host name, which changes
  with every container. Mnesia is an included application: loaded with the
  release, started by `Carry.Store` after pointing it at `AAAS_DB_DIR`.
  `carry_propagations` is `disc_only_copies` (dets), so the log costs
  disk, not memory. Migrations are JSON files (`migrations/NNNN_*.json`,
  the format of `successor`, ADR-0016) with the operation `createTable`;
  its `documentation` becomes the table's user property
  `aaas_documentation`, the Mnesia counterpart of `COMMENT ON`; applied
  files are recorded in `carry_migrations`. The service refuses to start
  when the table's attributes differ from the code's.
- **Retention.** Records older than `AAAS_RETENTION_HOURS` (default 24 h;
  an addition lasts at most about 35 minutes) are deleted every hour
  (`CLAUDE.md` 6.6). A record is about 0.96 KB, the largest addition
  writes about 10 000.
- **Kafka through brod.** brod 4.7.0 (pure Erlang except the crc32cer NIF,
  built from source), message key `taskId` with brod's hash partitioner,
  `required_acks: -1`, 1 s acknowledgement timeout, two retries. brod has
  no idempotent producer; a retried produce request can store a message
  twice with the same `eventId`, which consumers deduplicate (`CLAUDE.md`
  4.2). The client runs under brod's own supervisor, which restarts it
  every 5 s while the broker is unreachable, so a broker outage answers
  `UNAVAILABLE` and fails `/health` without stopping the service (the
  first build put the client in the service's supervision tree, and an
  unreachable broker stopped the whole application within a second).
- **Event contract.** New schema `aaas.carry.propagated.v1`: payload
  `digits`, `position`, `result` (least significant first);
  `validate-events.py` checks that `result` is the number plus 10 to the
  power of `position`. The unit tests validate every event they publish.
- **Memory and CPU at 128 MiB and 0.5 CPU (measured).** The release runs
  in interactive mode: the default embedded mode loads every module of
  every dependency at boot (35 MB of code), 98 MiB at rest and a peak of
  126 MiB under load; interactive mode loads modules when first used:
  35 MiB at rest, a peak of 50 MiB. One scheduler (`+S 1:1 +SDcpu 1:1`)
  instead of one per host core: with 8 concurrent callers p90 10 ms and a
  peak of 50 MiB, against 66 ms and 55 MiB with two schedulers and 9 ms
  and 61 MiB with eight. Busy waiting of schedulers is off and the process
  and port tables are sized for the connection limits.
- **Logging.** A formatter of the `:logger` default handler renders every
  event, the libraries' included, as one JSON line with the fields of
  `CLAUDE.md` 6.1. The emulator's last words on a failed start
  (`Kernel pid terminated …`) are printed by the BEAM itself and stay
  plain text; the service's own `carry did not start` line before them is
  JSON. Crash dumps are disabled (`ERL_CRASH_DUMP_SECONDS=0`); a failed
  start exits with status 1.
- **Shutdown.** SIGTERM is handled by the BEAM (`init:stop`):
  `prep_stop/1` suspends the gRPC listener and waits up to 5 s for the
  calls in progress, then the supervisor stops the listeners and Mnesia is
  stopped cleanly.
- **Formatting, linting, documentation.** `mix format` (100 columns) and
  Credo in strict mode with `Readability.Specs`; compilation with warnings
  as errors in every environment. Modules and public functions carry
  `@moduledoc`/`@doc` with the fields of `CLAUDE.md` 6.5.3 as bold labels
  and a `@spec`; private functions, private types and constants carry a
  `#` comment with those fields. Two gates: Doctor (100% docs and specs of
  public definitions) and `tools/doc_coverage.exs`, which parses the
  sources and checks every definition, private ones included, for its
  summary and fields. `iex>` examples are doctests; examples of private
  functions are prose, because private functions cannot be called from a
  doctest. ExDoc renders the API documentation for the portal.
- **Known advisory.** `mix hex.audit` reports EEF-CVE-2026-43966 in cowlib
  2.21.0 (no fixed version). The function concerned encodes structured
  header fields; the service never builds one from external input. The
  audit is therefore not a lint gate; the advisory is in the threat model.

## Consequences

- P2.13b makes `successor` call `Propagate`; the latency the successor
  sees is about 1 ms per carry (CAPACITY.md).
- The first module use after a start loads code from disk (interactive
  mode): the first call is a few milliseconds slower.
- A second instance of the service would have its own log (Mnesia is
  local); a retried call reaching it would be computed again with a new
  `eventId`, still correct.
- The dets file does not shrink after deletions; its space is reused, and
  dets refuses writes beyond 2 GB (about 2 million records), which the
  retention keeps far away.
