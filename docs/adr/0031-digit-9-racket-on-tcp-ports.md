# ADR-0031: digit-9 — Racket on TCP ports, SQLite through the FFI

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-25 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.12 |

## Context

`CLAUDE.md` 2 assigns digit 9 to Racket with SQLite. Step P2.12 must
reproduce the reference behaviour of `digit-0` (ADR-0022), with the
successor 0 and a carry, and pass `make contract-digit-9` (ADR-0021).
`CLAUDE.md` 6.5.3 names Scribble as the documentation tool, and
`CLAUDE.md` 6.2 requires arm64 images and a default limit of 128 MB for
interpreted and VM languages.

The official Racket images (`racket/racket`) are built for amd64 only.
Alpine 3.24 packages Racket 9.2 (Racket CS, on Chez Scheme) for arm64 and
amd64 as the minimal distribution: the runtime and the base collections,
without the package collections (`db`, `rackunit`, Scribble, `raco exe`).
Racket's web server and its `db` library are packages of the full
distribution. Measured on this host, a process with `racket/base` holds
about 72 MiB of anonymous memory, mostly the Chez Scheme and Racket boot
files and the macro expander; requiring `db/sqlite3` raises it to
142 MiB, because the library loads the contract and class systems.

## Decision

- **Racket 9.2 on Alpine 3.24** (`racket=9.2-r0`, pinned). Every other
  package comes from the catalog of the 9.2 release
  (`download.racket-lang.org/releases/9.2/catalog/`), so its version
  matches the runtime: compiler-lib (`raco exe`, `raco test`),
  rackunit-lib, scribble-lib and, for the linter, typed-racket-lib and
  macro-debugger-text-lib.
- **No `db` library: SQLite through the FFI.** `src/digit9/sqlite.rkt`
  binds the twelve functions of the SQLite C API the store needs
  (`ffi/unsafe`, `libsqlite3.so.0` of Alpine's `sqlite-libs`). The logic of
  the digit and the access to the database stay in Racket (`CLAUDE.md`
  4.4). A foreign call blocks the Racket virtual machine for its duration;
  each statement reads one row.
- **HTTP/1.1 server on Racket TCP ports** (`src/digit9/server.rkt`,
  `src/digit9/http.rkt`), the design of `digit-6` (ADR-0028) and `digit-8`
  (ADR-0030), with the same limits:
  - keep-alive, closed after 10 s of silence (`sync/timeout` on the
    port);
  - heads up to 8 KiB (431 above);
  - bodies up to 64 KiB, read and discarded, by `Content-Length` or
    chunked (413 above; 400 for ambiguous framing);
  - at most 256 connections;
  - a lingering close capped at 200 ms and 16 KiB.

  An accept thread starts one Racket thread per connection, under a
  custodian of its own that owns the connection's ports, so the stop can
  shut down what is left at once. Racket threads are green threads of one
  operating-system thread and are reclaimed by the garbage collector when
  they end; nothing has to be joined, unlike in `digit-8`. The contract is
  called under one semaphore, so the store and the metrics are never used
  concurrently. A connection is a pair of ports, so the framing is tested
  over string ports and pipes. Each connection reads into one buffer of
  4 KiB, compacted or doubled when needed; under the head limit it stays at
  most 16 KiB.
- **Signals.** Racket turns SIGTERM, SIGHUP and SIGINT into breaks of the
  main thread. Breaks are disabled until the server listens and then
  awaited with `sync/enable-break`. The stop closes the listener, wakes the
  idle connections through an event their readers wait on (a request in
  progress is not woken), waits up to 5 s for running requests and then
  shuts down the custodians that are left.
- **Memory guard.** Racket CS keeps the memory its minor collections free
  mapped, and starts a major collection only when the heap has doubled
  since the previous one: near 130 MiB with a runtime of about 60 MiB of
  heap, above the limit. Ten rounds of 512 concurrent connections with 1 MB
  heads reached a `memory.peak` of 125 MiB in the first build, and the
  process kept 111–119 MiB after them. `src/digit9/memory.rkt` checks the
  memory the runtime holds from the system (Chez Scheme's
  `current-memory-bytes`, through `ffi/unsafe/vm`) every 200 ms and runs a
  major collection when it is 12 MiB above its size after the previous
  collection. A major collection takes 3–5 ms, because the runtime lives
  in the static generation. With the guard and the reused input buffer,
  the same flood peaked at 86.1 MiB and left the process at 69–74 MiB.
- **Runtime.** `raco exe` builds the executable from the `main` submodule
  of `src/digit9/main.rkt`, with the modules it uses embedded, and
  `raco distribute` adds the Racket CS runtime. The runtime image is
  Alpine 3.24 with the libraries of the runtime (ncurses, zlib, lz4) and
  `sqlite-libs`, user 10001: 84 MB, of which the runtime is 53.5 MB. The
  executable and `racket` hold the same memory (70–72 MiB).
- **Formatter and linter: fmt (`raco fmt`) and review (`raco review`)**,
  the Racket formatter and linter of the package catalog, both outside the
  distribution, installed from pinned Git commits (fmt `4e1ed68`, its pretty-expressive `27e7be8`, review
  `ecb1968`). fmt is installed without its documentation dependency
  (`racket-doc`, the whole Racket manual). review starts by resolving a
  table of modules of the full distribution (among them the GUI library);
  the six packages of that table it does not otherwise need are installed
  as sources only (`--no-setup`, nothing compiled, 26 MB), last. The lint
  stage fails when fmt (width 100) would change a file, a line is longer
  than 100 characters, a module does not compile or review reports a
  problem.
- **Doc comments and coverage.** Racket has no docstrings, and Scribble's
  in-source documentation (`scribble/srcdoc`) covers exported bindings
  only. Every module-level definition, private ones included, therefore
  carries a `;;` doc comment directly above it with the fields of
  `CLAUDE.md` 6.5.3; the summary is its first line, `Parameters:` and
  `Fields:` list every parameter or field as `  - name: ...`.
  `tools/doc-coverage.rkt` reads each module with `read-syntax` for its
  definitions and the file for the comments, and requires:
  - procedures: Parameters (exactly the parameters, in order), Returns,
    Errors, Side Effects, Complexity, Thread Safety, Owner, Since and
    Example;
  - structs: Fields (exactly the fields), Thread Safety, Owner, Since and
    Example;
  - exported procedures and structs: also Business Justification;
  - constants and submodules: a summary.

  Definitions inside procedure bodies are local variables and are not
  checked. The language has no `doc-definitions.psv` row: like Swift and
  D, it has its own gate.
- **Examples are tests.** An `Example:` line `  > expression` (continued
  on lines indented by four spaces) is evaluated inside its module
  (`module->namespace`, so private definitions are reachable) by
  `tests/examples-test.rkt`, and the printed result is compared with the
  lines that follow. Other example lines are shown, not evaluated.
- **API documentation with Scribble.** `tools/api-docs.rkt` builds a
  Scribble document from the doc comments (a section per module, a
  subsection per definition with its signature, private ones included)
  and renders it with Scribble's HTML renderer for the portal.
- **Memory limit: 128 MB**, the default for interpreted and VM services.

## Consequences

- `digit-9` passes the contract test 8/8 with `carry: true`, and the ten
  digit services are complete. Its edge cases answer as in `digit-6`,
  `digit-7` and `digit-8`.
- Performance:
  - 0.073–0.100 ms per call on a persistent connection;
  - 0.18 ms with a new connection per call;
  - 70.9 MiB idle and 76.7 MiB with 256 connections;
  - the memory guard costs 0.1–0.3% of a CPU when idle (five checks a
    second).
- Idle memory is dominated by the Racket runtime, about ten times that of
  `digit-8`; it fits the default limit with a third of it to spare.
- The lint, test and documentation stages depend on the Racket package
  catalog and on GitHub: they are downloaded again after every
  `make prune-stages`. The runtime image does not depend on them.
- The memory guard is a rule of this process's own code; a later Racket
  service near its memory limit needs the same guard or another way to
  return freed memory to the system.
- The doc comment format and its gate are Racket conventions of this
  repository, not a Racket standard; the example tests keep the examples
  true.
