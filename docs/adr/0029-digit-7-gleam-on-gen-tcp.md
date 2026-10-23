# ADR-0029: digit-7 — Gleam with its own HTTP server on gen_tcp

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-23 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.10 |

## Context

`CLAUDE.md` 2 assigns digit 7 to Gleam with SQLite. Step P2.10 must reproduce
the reference behaviour of `digit-0` (ADR-0022) and pass
`make contract-digit-7` (ADR-0021). `CLAUDE.md` 6.5.3 names `gleam docs`
as the documentation tool, and 6.5.4 leaves Gleam to
`scripts/doc-check.sh`, because Gleam has no coverage tool of its own.

Gleam compiles to Erlang and runs on the BEAM. Its HTTP server packages
(`mist` on `glisten`) do not offer every limit of the earlier digit
services: a total head size answered with 431, a cap on open connections,
or a lingering close. `digit-4`, `digit-5` and `digit-6` enforce these
(ADR-0026 to ADR-0028).

## Decision

- **Gleam 1.19.2 on Erlang/OTP 28.**
  - Toolchain: the `erlang:28.5.0.8-alpine` image, plus the musl build of
    Gleam, checked against its release SHA-256.
  - Gleam's own layout (`src/`, `test/`, `dev/`): `gleam test` only reads
    `test/`, and `gleam run -m` finds tools in `dev/`. The Dart service
    already uses its language's layout (ADR-0027).
- **Dependencies** from Hex, locked by version and checksum in
  `manifest.toml`:
  - `gleam_stdlib`, `gleam_erlang` and `gleam_otp`;
  - `sqlight`, with the `esqlite` NIF, which embeds the SQLite
    amalgamation and is compiled from source in the toolchain stage;
  - `envoy`;
  - for tests and the coverage gate only: `gleeunit` and `glance`.

  Hex serves small tarballs, so the build does not repeat the slow git
  clone of ADR-0028. No Erlang source is added: every Erlang function
  the service calls (`gen_tcp`, `inet`, `file`, `calendar`, `os`,
  `gen_event`) is a typed `@external` in Gleam. Option lists are Gleam
  constructors whose Erlang form is the option term.
- **HTTP/1.1 server on `gen_tcp`**:
  - The framing is in `src/digit7/http.gleam`. It ports the rules and
    limits of `digit-6`: keep-alive closed after 10 s of silence, heads up
    to 8 KiB (431 above), bodies up to 64 KiB read and discarded (413
    above; 400 for ambiguous framing), and a lingering close capped at
    200 ms per read and 16 KiB.
  - The framing is pure: a `Reader` takes an input function, so tests
    feed it prepared bytes. Lines are read as Latin-1, so any byte
    sequence is a valid string.
  - Sockets are passive, and one receive returns at most 16 KiB
    (`{buffer, 16384}`). A send blocked for 10 s closes the socket.
- **Processes**:
  - A chain of acceptors. The process that accepts a connection spawns
    the next acceptor and then serves the connection itself. It owns the
    socket, so the socket closes whenever the process ends.
  - The **contract process** (an OTP actor, `src/digit7/api.gleam`) owns
    the SQLite connection and the counters. Connection processes call it
    and wait at most 5 s; a later answer is a 503. This is the BEAM form
    of the single mutex of ADR-0028.
  - The **tracker** (an OTP actor, `src/digit7/tracker.gleam`) admits at
    most 256 connections and monitors each one, so a crashed connection
    frees its slot. It knows which connections are busy. On stop it
    refuses new connections, kills the idle ones and waits up to 5 s for
    the busy ones.
- **SIGTERM.** By default, the runtime's `erl_signal_server` answers
  SIGTERM with `init:stop()`. `src/digit7/signal.gleam` is a `gen_event`
  handler written in Gleam: its callbacks compile to the Erlang module
  `digit7@signal`. It replaces the default handler and turns SIGTERM into
  a message, so the main process logs, drains and halts with status 0.
  SIGINT is not handled: `os:set_signal/2` does not support it.
- **File header.** `gleam format` moves module comments (`////`) above
  every other line. The `gleam` header type therefore writes the header
  as a module comment, and it becomes the start of the module's
  documentation.
- **Runtime image**:
  - Alpine 3.24.3 with the three shared libraries of `beam.smp`
    (ncurses, libstdc++, libgcc).
  - Only the boot files, the emulator, `kernel` and `stdlib` of
    Erlang/OTP; the rest of OTP is left out.
  - The `gleam export erlang-shipment` packages, found through
    `ERL_LIBS`.
  - busybox `wget` for the healthcheck.
  - The emulator runs with `+sbwt none` (and its dirty variants), so idle
    schedulers do not spin on the CPU quota.
  - `+P 4096` and `+Q 1024` size the process and port tables for 256
    connections. The defaults (about one million processes, 65 536 ports)
    cost 17 MB more at start-up.
- **Lint**: `gleam format --check` and `gleam build --warnings-as-errors`.
- **Documentation coverage**:
  - **Gate:** `dev/doc_coverage.gleam` parses every module with `glance`.
    It requires a module comment after the header, and a `///` comment on
    every function, external, constant, type alias, custom type and
    constructor, public and private.
  - **Docs build:** `gleam docs build` must succeed.
  - **Repository check:** `scripts/doc-check.sh` gets a `gleam` row.
  - **Portal:** the export documents the public definitions, which is all
    that `gleam docs` renders.
- **Memory limit: 128 MB**, the default for interpreted and VM languages
  (`CLAUDE.md` 6.2).

## Consequences

- `digit-7` passes the contract test 8/8. Its edge cases answer as in
  `digit-6`, with one difference: a request head of 200 KB or more is
  answered 431 instead of being cut off with a reset.
- Performance and memory (CAPACITY.md):
  - 0.18 ms per call on a persistent connection;
  - 0.25 ms with a new connection per call;
  - 23.5 MiB idle, about 20 times `digit-6`, since that is what the
    Erlang runtime needs.
- Floods of 512 connections with 1 MB heads raise the resident size to
  between 54 and 91 MiB. The runtime's own usage stays at about 15 MB:
  this is allocator memory kept for reuse, not a leak. It stays below
  the 128 MB limit.
- Unlike the earlier digit services, a crash while serving a connection
  is contained in one process. The socket closes and the tracker frees
  the slot; the other connections are not affected.
- The esqlite NIF is the only native code. It is built from source in
  every toolchain build, which needs the C compiler (`build-base`) and
  the rebar3 plugin `pc` from Hex.
- The private definitions do not appear in the portal. Their
  documentation is in the source, and the coverage gate enforces it.
- A later Gleam service (none is planned) would reuse the `gleam` header
  type, the doc-check row and the coverage tool.
