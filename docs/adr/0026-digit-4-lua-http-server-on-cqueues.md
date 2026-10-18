# ADR-0026: digit-4 — Lua with its own HTTP/1.1 server on cqueues

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-18 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.7 |

## Context

`CLAUDE.md` 2 assigns digit 4 to Lua with SQLite. Step P2.7 must reproduce
the reference behaviour of `digit-0` (ADR-0022) and pass
`make contract-digit-4` (ADR-0021). `CLAUDE.md` 6.5.3 names LDoc as the
documentation tool. LDoc documents what carries a doc comment and silently
skips the rest, so on its own it cannot prove coverage.

Alpine 3.22, the base of the other Alpine digit services, packages Lua 5.4.7
with cqueues (a coroutine event loop with sockets and signals), lsqlite3,
luaposix, busted, luacheck, StyLua and LDoc. It packages lua-http, the
mature HTTP server for Lua, only up to Lua 5.3, and the 5.3 package also
needs luaossl and its other dependencies. OpenResty and Lapis would bring an
nginx and a web framework for four GET endpoints.

## Decision

- **Lua 5.4.7 from Alpine 3.22.2**, every package pinned to its exact
  version. The runtime image holds the interpreter, cqueues, lsqlite3 and
  luaposix; it is 20.9 MB.
- **Own HTTP/1.1 server in Lua on cqueues** (`src/digit/http.lua`), in place
  of lua-http on an older Lua or a wrapper. The digit logic, the database
  access and the HTTP handling are all Lua; no wrapper is needed
  (`CLAUDE.md` 4.4). The server:
  - runs one coroutine per connection on one cqueues controller, so a slow
    or idle client delays only itself;
  - keeps connections open (HTTP/1.1 keep-alive; HTTP/1.0 only on request)
    and closes them after 10 s of silence;
  - accepts at most 256 connections at once and closes further ones on
    accept;
  - answers 431 for a head above 8 KiB (lines are capped at that size) and
    400 for a malformed request line or header field;
  - reads and discards request bodies up to 64 KiB (`Content-Length` or
    chunked) and answers 413 above that without reading. A request with
    both `Content-Length` and `Transfer-Encoding`, another transfer coding
    or an invalid length answers 400 (RFC 9112, 6.1 and 6.3);
  - closes a connection with a lingering close: it shuts the write side down
    and discards incoming input for up to 200 ms, because closing a socket
    with unread input makes the kernel send a reset that destroyed the 431
    answer in the first measurement;
  - installs an error handler on every socket that returns the error code.
    The default handler of cqueues raises, which turned a port in use into
    an uncaught error instead of a JSON log line, and could end the event
    loop on a connection reset.
- **SIGTERM and SIGINT through cqueues.signal.** Both signals are blocked
  and read from a signalfd by a coroutine. The accept loop polls the stop
  flag every 200 ms, idle connections are shut down, and running requests
  get up to 5 s to finish. The service stops in about 150 ms.
- **SQLite through lsqlite3**, mirroring `digit-0`'s store. Failures follow
  the Lua convention (`nil` and a message). luaposix provides the
  millisecond clock of the log lines (`gettimeofday`) and the listing of the
  migrations directory.
- **Formatter and linter.**
  - StyLua 2.0.2 formats the code (`stylua.toml`, 120 columns);
  - luacheck 0.26.1 checks it against the Lua 5.4 standard library;
  - `luac5.4 -p` compiles every file.

  luacheck runs on Lua 5.1, its Alpine package, which does not matter: it
  only parses the sources.
- **Documentation coverage** has two parts:
  - `tools/doc-coverage.lua` requires an LDoc comment (a block starting
    with `---`) above every named function at any depth, every
    module-level constant and table, every module field and every class
    table, plus an `@module` or `@script` tag per file;
  - LDoc runs with `--all` (local functions included) and
    `--fatalwarnings`, so a parameter documented under the wrong name or a
    broken reference fails the build.

  A class table is assigned to a local declared earlier, so that its
  constructor comes before its `@type` block. Otherwise LDoc lists the
  constructor as a method. `scripts/doc-check.sh` gains a `lua` row (a
  comment above every top-level function). The header type `lua` also
  covers `.busted`, `.luacheckrc` and `config.ld`.
- **Tests: busted 2.2.0**, 22 tests against the real migrations. The HTTP
  transport is tested through a connection double that replaces the socket.
- **Memory limit: 128 MB**, the default for interpreted services
  (`CLAUDE.md` 6.2), although the service uses 1.8 MiB idle and 3.1 MiB
  with 256 open connections.

## Consequences

- `digit-4` passes the contract test 8/8. Every edge case measured on
  `digit-0` answers the same, except that a malformed request line answers
  400 (as in `digit-2`) instead of a silent close.
- The service is as fast as the compiled digits: 0.09 ms per call on a
  persistent connection, 0.19 ms with a new connection per call, and
  4 000 calls from 8 concurrent clients in 0.25 s.
- The HTTP parser is code this repository owns and tests. It implements
  what the digit contract needs (no TLS, no HTTP/2, no request bodies used
  by the handler) and is covered by the unit tests and the edge-case runs
  recorded in the step log.
- Future Lua services (none planned) can reuse the server module, the
  toolchain and the coverage gate.
