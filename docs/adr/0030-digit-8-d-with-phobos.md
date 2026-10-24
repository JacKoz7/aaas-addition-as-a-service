# ADR-0030: digit-8 — D with Phobos and no dub dependencies

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-24 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.11 |

## Context

`CLAUDE.md` 2 assigns digit 8 to D with SQLite. Step P2.11 must reproduce
the reference behaviour of `digit-0` (ADR-0022) and pass
`make contract-digit-8` (ADR-0021). `CLAUDE.md` 6.5.3 names ddoc as the
documentation tool, and `CLAUDE.md` 6.2 requires arm64 images.

D has three compilers. DMD, the reference compiler, has no arm64 build.
GDC follows the GCC release cycle and lags the language. LDC, the LLVM D
compiler, supports arm64 and is packaged by Alpine. The common D web
framework, vibe.d, brings an event loop and many dub packages. Phobos, the
standard library, has TCP sockets (`std.socket`), threads (`core.thread`)
and a binding to the SQLite C API (`etc.c.sqlite3`).

## Decision

- **LDC 1.42 on Alpine 3.24**, from Alpine's packages (`ldc`, `dub`, `gcc`,
  `musl-dev`, the SQLite and zlib libraries), all pinned. The dub package
  (`dub.sdl`) has **no dependencies**. The new header type `sdl` gives
  `dub.sdl` its file header.
- **HTTP/1.1 server on Phobos sockets** (`src/digit8/server.d`,
  `src/digit8/http.d`), the design of `digit-6` (ADR-0028):
  - keep-alive, closed after 10 s of silence (`SO_RCVTIMEO`);
  - heads up to 8 KiB (431 above);
  - bodies up to 64 KiB, read and discarded, by `Content-Length` or
    chunked (413 above; 400 for ambiguous framing);
  - at most 256 connections;
  - a lingering close capped at 200 ms and 16 KiB.

  An accept thread starts one druntime thread with a 256 KiB stack per
  connection. The contract is called under one mutex, so the store and the
  metrics are never used concurrently. Reads and writes call `recv` and
  `send` on the descriptor and retry on `EINTR`: the garbage collector
  suspends threads with signals, which interrupts a receive that has a
  timeout even with `SA_RESTART`.
- **Joining ended threads.** A druntime `Thread` is created joinable, and
  its stack stays mapped until it is joined or the garbage collector
  finalises the `Thread` object. The first build did neither: ten rounds
  of a flood of 512 connections left about 2 350 stacks behind, 9 MiB per
  round, until the memory limit stopped the container in round ten. Each
  connection thread now records itself as the last ended thread and joins
  the one recorded before it, so at most one ended thread waits. A unit
  test checks that 100 connections leave no stacks behind.
- **Signals.** SIGTERM and SIGINT are blocked before any thread starts and
  awaited with `sigwait` on the main thread. The stop shuts the listener
  and the idle connections down and waits up to 5 s for running requests.
  All threads are daemon threads, so the process ends when `main`
  returns.
- **Memory safety.** The framing, the contract, the metrics and the trace
  parsing are `@safe`. `@trusted` code is limited to the calls of C
  interfaces (sockets, SQLite, signals, the write of log lines) and the
  locks around them. The image build (`dub build --build=production`)
  optimises without `releaseMode`, so bounds checks and assertions stay on.
- **Runtime.** The executable is linked statically against musl, druntime,
  Phobos, SQLite and zlib (`-static`; zlib is part of every static Phobos
  executable). The runtime image is `scratch` with the stripped
  executable, the migrations and a static busybox as `wget`: 6.49 MB.
- **Formatter and linter: dfmt and D-Scanner 0.15.2.** Alpine packages
  neither, and their releases have no arm64 binaries, so the Dockerfile
  builds both from their dub packages in a stage of their own. The lint
  stage fails when dfmt would change a file (dfmt has no check mode) or
  D-Scanner reports a warning. D-Scanner runs its defaults plus the checks
  for documented parameters and return values and for sorted imports, with
  a line limit of 100. Two checks are off: `could_be_immutable_check`
  (it asks for `const` on every local assigned once) and
  `allman_braces_check` (dfmt places the braces, and the check flags the
  inline delegate literals dfmt writes). Every target is also built with
  warnings and deprecations as errors.
- **Documentation coverage.** ddoc does not fail on undocumented
  declarations, and D-Scanner checks public ones only. The compiler's JSON
  description (`ldc2 -D -X`; the `comment` field is filled only with `-D`)
  lists every declaration with its protection. `tools/doc_coverage.d`
  requires a ddoc comment on every module and every declaration at any
  depth, private ones included. It skips imports, unittest blocks and the
  `_d_cmain` mixin the compiler adds for `main`. ddoc runs with `-w`, so a
  `Params` entry that names no parameter fails the stage. The portal gets
  ddoc's HTML of the `src` modules (ddoc leaves private declarations out).
  The language has no `doc-definitions.psv` row: like Swift, it has its own
  gate.
- **Tests: `dub test`**, 61 `unittest` blocks. The blocks directly after a
  declaration in `src/` are ddoc's documented unit tests: they are the
  declaration's example in the documentation and run with the others
  (`CLAUDE.md` 6.5.3, Example). `tests/digit8_tests/` holds the rest: the
  contract and the migrations, the framing through a connection double,
  and the server over TCP. `dub test` leaves the main source file out of
  the test build, so `src/digit8/app.d` holds only `main`, and the
  process lives in `src/digit8/service.d`.
- **Memory limit: 64 MB**, the default for compiled services.

## Consequences

- `digit-8` passes the contract test 8/8. Its edge cases answer as in
  `digit-6` and `digit-7`.
- Performance:
  - 0.037 ms per call on a persistent connection;
  - 0.17 ms with a new connection per call;
  - 3.2 MiB idle and 25 MiB with 256 connections;
  - ten rounds of the flood peaked at 27 MiB. The garbage-collected heap
    keeps about 16 MiB after a burst and reuses it for the next one.
- The image holds no C library, shell or package manager.
- The lint toolchain depends on the dub registry: dfmt and D-Scanner are
  downloaded again after every `make prune-stages`. The runtime image and
  the tests do not depend on it.
- Joining the previous thread from each ending connection thread is a rule
  of the server's own code; a later D service with threads must follow it
  or join its threads in another way.
