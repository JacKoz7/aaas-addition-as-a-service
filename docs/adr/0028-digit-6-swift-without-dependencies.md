# ADR-0028: digit-6 — Swift without package dependencies

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-19 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.9 |

## Context

`CLAUDE.md` 2 assigns digit 6 to Swift with SQLite. Step P2.9 must reproduce
the reference behaviour of `digit-0` (ADR-0022) and pass
`make contract-digit-6` (ADR-0021). `CLAUDE.md` 6.5.3 names DocC as the
documentation tool. The Swift standard library has no HTTP server, and
Foundation on Linux has none either.

The first design used SwiftNIO 2.103.0, the standard Swift server
framework. SwiftPM fetches a dependency by cloning its full git history:
about 86 000 objects for SwiftNIO, plus its own dependencies. On the
network this step ran on (30–100 KB/s), the clone broke off after 16
minutes. A Docker build fetches the dependencies again after every
`make prune-stages` (`CLAUDE.md` 6.6), so every rebuild would have
depended on that download.

## Decision

- **Swift 6.3.3**, the `swift:6.3.3-noble` image, with Ubuntu's
  `libsqlite3-dev` pinned. The package has **no dependencies**: the build
  fetches nothing beyond the base image. The targets live in `src/` and
  `tests/` like every AaaS service. The manifest's
  `// swift-tools-version:` line must come first, so the new header type
  `swiftpm` puts it before the file header as a preamble.
- **HTTP/1.1 server on POSIX sockets** (`src/DigitService/Server.swift`).
  It has the behaviour and limits of `digit-4` and `digit-5` (ADR-0026,
  ADR-0027):
  - keep-alive, closed after 10 s of silence (`SO_RCVTIMEO`);
  - heads up to 8 KiB (431 above);
  - bodies up to 64 KiB, read and discarded, by `Content-Length` or
    chunked (413 above, answered at once; 400 for ambiguous framing);
  - at most 256 connections;
  - a lingering close capped at 200 ms and 16 KiB.

  Each connection runs on a detached thread with a 256 KiB stack. The
  contract is called under one `Synchronization.Mutex`, so the store and
  the metrics are never used concurrently. For that reason the classes
  that hold them are declared `@unchecked Sendable`.
- **SQLite through its C API**, imported by a system library target
  (`src/CSQLite`: `module.modulemap` and `shim.h`; the module map gets the
  `swift` header type).
- **Signals.** SIGTERM and SIGINT are blocked before any thread starts and
  awaited with `sigwait` on the main thread. The stop:
  - shuts the listening socket and the idle connections down;
  - waits up to 5 s for running requests;
  - takes about 25 ms in the process.
- **Logging without Foundation.** Each log line is written with one
  `write(2)` on descriptor 1, so lines from concurrent threads do not
  interleave. The timestamp comes from `clock_gettime` and `strftime`.
- **Runtime.** The release executable links the Swift runtime statically
  (`--static-swift-stdlib`). The runtime image is the distroless
  cc-debian13 image of `digit-3` (glibc, libgcc_s, libstdc++), with the
  SQLite library and a static busybox as `wget`. The image is 70.4 MB.
- **Lint**:
  - `swift format lint --strict`;
  - a build of every target with `-warnings-as-errors`.
- **Documentation coverage.**
  - **Gate:** DocC does not fail on undocumented declarations. The
    compiler writes symbol graphs down to private access, and
    `tools/doc-coverage.swift` requires a doc comment on every symbol
    located in the service's sources.
  - **Exemptions:** symbols the compiler synthesizes, and implicit
    initializers, which sit at the line of their type.
  - **DocC:** runs with `--warnings-as-errors`.
- **Tests: swift-testing** (shipped with the toolchain), 23 tests. They
  run against the real migrations and test the transport through a
  connection double and over TCP.
- **Memory limit: 64 MB**, the default for compiled services.

## Consequences

- `digit-6` passes the contract test 8/8. Its edge cases answer as in
  `digit-4` and `digit-5`. One difference: a client that keeps sending a
  head of 200 KB or more after the 431 is cut off after 16 KiB and sees a
  connection reset instead of the 431.
- Performance:
  - 0.08 ms per call on a persistent connection;
  - 0.19 ms with a new connection per call;
  - 1.1 MiB idle and 10.1 MiB with 256 connections;
  - two floods of 256 connections with 1 MB heads, three times, left the
    service healthy at 10.1 MiB.
- The service owns its HTTP code and threading. That is more code than a
  SwiftNIO handler, but it is covered by the unit tests and the edge-case
  runs recorded in the step log.
- A later Swift service that needs packages will meet the same download.
  A package mirror or vendored sources would then need their own ADR.
