# ADR-0027: digit-5 — Dart with its own HTTP/1.1 server on dart:io sockets

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-19 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.8 |

## Context

`CLAUDE.md` 2 assigns digit 5 to Dart with SQLite. Step P2.8 must reproduce
the reference behaviour of `digit-0` (ADR-0022) and pass
`make contract-digit-5` (ADR-0021). `CLAUDE.md` 6.5.3 names dartdoc as the
documentation tool.

Dart ships an HTTP server in its standard library (`HttpServer` of
`dart:io`). The first implementation used it. The edge-case runs then
showed two defects that its API cannot fix:

- It accepts request heads of up to 1 MiB, a constant of its parser, and
  buffers them. Fewer than 16 connections that each sent a 1 MB head made
  the service exceed its 64 MB memory limit and be killed by the kernel.
  The digit services have no restart policy, so the container stayed down.
- It sends an answer only after it has consumed the request body. A 413
  for a declared body above 64 KiB therefore waited until the client sent
  the whole body.

The `sqlite3` package (3.x) uses build hooks. By default they download a
prebuilt SQLite from GitHub during the build. `dart compile exe` refuses
packages with build hooks.

## Decision

- **Dart 3.13.4**, the `dart` image of that version (Debian 13), with every
  package pinned to an exact version in `pubspec.yaml` and locked with its
  checksum in `pubspec.lock` (`dart pub get --enforce-lockfile`). The
  service follows the Dart package layout (`bin/`, `lib/`, `test/`,
  `tool/`), which `dart build`, `dart test` and `dart doc` expect. A
  service `.gitignore` re-includes `bin/`, which the repository rules
  ignore as build output.
- **Own HTTP/1.1 server on `dart:io` sockets** (`lib/src/server.dart`), as
  `digit-4` does in Lua (ADR-0026), in place of `HttpServer`. It has the
  same behaviour and limits:
  - one asynchronous task per connection;
  - keep-alive, and a 10 s idle timeout;
  - heads up to 8 KiB (431 above);
  - bodies up to 64 KiB, read and discarded, by `Content-Length` or
    chunked (413 above, answered at once; 400 for ambiguous framing);
  - at most 256 connections;
  - a lingering close, capped at 16 KiB. Without the cap, discarding the
    input of 256 flooding connections allocated faster than the garbage
    collector freed it, and the service was killed again.

  With these limits, two clients that each opened 256 connections with
  1 MB heads, repeated six times, peaked the service at 16.8 MiB.
- **SQLite from the system.** The `sqlite3` package is told to load the
  library of the operating system (`hooks: user_defines: sqlite3: source:
  system`), so the build downloads no binary. The runtime image holds
  Debian's `libsqlite3.so.0`, under the name the package opens
  (`libsqlite3.so`).
- **AOT executable with `dart build cli`**, because `dart compile exe`
  refuses packages with build hooks. The runtime image is `scratch` with:
  - `/runtime` of the SDK image (glibc and the loader), as the Dart image
    documents;
  - the SQLite library;
  - the executable;
  - a static busybox as `wget` for the exec-form healthcheck.

  The image is 19.5 MB.
- **Lint**:
  - `dart format` check;
  - `dart analyze --fatal-infos` with the recommended lints, strict casts,
    inference and raw types, and `public_member_api_docs`.
- **Documentation coverage** has two parts:
  - `tool/doc_coverage.dart` parses every file with package:analyzer and
    requires a `///` comment on the library directive and every
    declaration, public and private (the lint covers public members only);
  - dartdoc must report `Found 0 warnings and 0 errors`.

  Every package in the pubspec is pinned to an exact version. `pubspec.lock`
  is generated, so it is exempt from the header check
  (`.doc-check-ignore`).
- **Tests: package:test**, 23 tests. They run against the real migrations
  and test the HTTP transport through a stream and a sink, and over TCP.
- **Memory limit: 64 MB**, the default for compiled services.

## Consequences

- `digit-5` passes the contract test 8/8. Its edge cases answer as in
  `digit-4`: a garbage request line answers 400, where `digit-0` closes
  silently.
- It takes 0.13 ms per call on a persistent connection and 0.33 ms with a
  new connection per call. 8 concurrent clients make 4 000 calls in
  0.40 s. Memory is 2.5 MiB idle and 7.3 MiB with 256 idle connections.
- The HTTP code is owned by this repository and unit tested; `dart:io`
  still provides sockets, timers and the event loop.
- The OOM finding showed that the digit services stop for good when
  killed: Compose gives them no restart policy. The documents of
  `digit-3`, which claimed a restart, were corrected in this step.
