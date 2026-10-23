//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/server.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         The HTTP/1.1 server of the digit service: a chain of
////                  acceptor processes, one process per connection,
////                  persistent connections, bounded requests and a
////                  graceful stop.
//// Related Docs:    services/digit-7/src/digit7/http.gleam, ADR-0028,
////                  ADR-0029
////
//// The HTTP server of the digit-7 service.
////
//// One process waits in `accept`. When a client connects, that process
//// spawns the next acceptor and becomes the connection process: it owns
//// the socket, so the socket closes whenever the process ends. Each
//// connection asks the tracker (`digit7/tracker`) to be admitted, then
//// serves requests until the client closes, goes silent for
//// `idle_timeout_ms`, sends a request that is rejected or asks to close.
//// Every reply comes from the contract process (`digit7/api`).

import digit7/api.{type Reply}
import digit7/http.{type Reader}
import digit7/log.{type Logger}
import digit7/socket.{type Socket}
import digit7/trace
import digit7/tracker
import gleam/bit_array
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// Milliseconds a connection may stay silent, between requests or within
/// one, before it is closed.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
pub const idle_timeout_ms = 10_000

/// Milliseconds a closing connection keeps reading what the client still
/// sends (lingering close, RFC 9112 9.6).
///
/// Owner: AEC. Since: digit-7 0.1.0.
const linger_ms = 200

/// Most bytes read during a lingering close.
///
/// Owner: AEC. Since: digit-7 0.1.0.
const linger_bytes = 16_384

/// A running server.
///
/// Thread Safety: an immutable handle; `stop` may be called once from any
/// process. Owner: AEC. Since: digit-7 0.1.0.
pub type Server {
  /// The listening socket, the bound port and the connection tracker.
  Server(listener: Socket, port: Int, tracker: Subject(tracker.Message))
}

/// What the connection process needs to serve requests.
///
/// Thread Safety: an immutable value shared by every connection process.
/// Owner: AEC. Since: digit-7 0.1.0.
type Context {
  /// The listener, the contract process, the tracker and the logger.
  Context(
    listener: Socket,
    contract: Subject(api.Message),
    tracker: Subject(tracker.Message),
    log: Logger,
  )
}

/// Start listening and accepting connections.
///
/// Business Justification: serves the digit contract on port 8080
/// (CLAUDE.md 4.4, 6.1).
/// Parameters: `port` — 0..65535 (0: any free port, for the tests);
/// `contract` — the contract process; `log` — the logger.
/// Returns: the server. Errors: the reason as text when the port cannot
/// be bound (`eaddrinuse`, `eacces`) or the tracker cannot start.
/// Side Effects: binds the port; spawns the tracker and the first
/// acceptor. Complexity: O(1). Thread Safety: safe; the caller owns the
/// listening socket and must stay alive while the server runs.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `start(8080, contract, logger)`.
pub fn start(
  port: Int,
  contract: Subject(api.Message),
  log: Logger,
) -> Result(Server, String) {
  use listener <- result.try(socket.listen(port, tracker.max_connections))
  case tracker.start() {
    Error(_) -> {
      socket.close(listener)
      Error("cannot start the connection tracker")
    }
    Ok(tracker) -> {
      let context = Context(listener:, contract:, tracker:, log:)
      process.spawn_unlinked(fn() { accept_loop(context) })
      Ok(Server(listener:, port: socket.port(listener), tracker:))
    }
  }
}

/// Stop the server.
///
/// Description: closes the listening socket (the waiting acceptor ends),
/// refuses new connections, closes the idle ones and waits up to
/// `tracker.drain_timeout_ms` for requests being answered; their replies
/// carry `Connection: close`.
/// Business Justification: a SIGTERM must not cut a reply in half
/// (graceful shutdown in at most 10 s, CLAUDE.md 6.1).
/// Parameters: `server` — the server. Returns: Nil when drained.
/// Errors: none. Side Effects: closes sockets, kills idle connection
/// processes. Complexity: O(n) in the connections.
/// Thread Safety: call once, from any process. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `stop(server)`.
pub fn stop(server: Server) -> Nil {
  socket.close(server.listener)
  tracker.stop(server.tracker)
}

/// Accept connections until the listener is closed.
///
/// Description: on a new connection, spawns the next acceptor and serves
/// the connection in this process. An accept failure other than `closed`
/// (for example `emfile`) is logged and retried after 100 ms.
/// Parameters: `context` — the server context. Returns: Nil when the
/// listener is closed. Errors: none. Side Effects: accepts sockets,
/// spawns processes, logs. Complexity: O(1) per connection.
/// Thread Safety: one acceptor at a time. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `accept_loop(context)`.
fn accept_loop(context: Context) -> Nil {
  case socket.accept(context.listener) {
    Error("closed") -> Nil
    Error(reason) -> {
      log.event(context.log, log.Warn, "accept failed", Some(reason))
      process.sleep(100)
      accept_loop(context)
    }
    Ok(connection) -> {
      process.spawn_unlinked(fn() { accept_loop(context) })
      case tracker.admit(context.tracker) {
        True -> serve(context, connection)
        False ->
          log.event(
            context.log,
            log.Warn,
            "connection limit reached or stopping; connection closed",
            Some(int.to_string(tracker.max_connections)),
          )
      }
      close(connection)
    }
  }
}

/// Close a connection with a lingering close.
///
/// Description: sends FIN, then reads and discards what the client still
/// sends for up to `linger_ms` per read and `linger_bytes` in total, so
/// the client receives the reply before a reset.
/// Parameters: `connection` — the socket. Returns: Nil. Errors: none.
/// Side Effects: shuts down and closes the socket. Complexity: O(1).
/// Thread Safety: socket owner. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `close(connection)`.
fn close(connection: Socket) -> Nil {
  socket.shutdown_write(connection)
  drain(connection, 0)
  socket.close(connection)
}

/// Read and discard input during a lingering close.
///
/// Parameters: `connection` — the socket; `discarded` — bytes so far.
/// Returns: Nil when the client closes, goes silent or `linger_bytes` is
/// passed. Errors: none. Side Effects: reads the socket.
/// Complexity: O(n). Thread Safety: socket owner. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `drain(connection, 0)`.
fn drain(connection: Socket, discarded: Int) -> Nil {
  case discarded > linger_bytes, socket.receive(connection, linger_ms) {
    True, _ | _, <<>> -> Nil
    False, chunk -> drain(connection, discarded + bit_array.byte_size(chunk))
  }
}

/// The problem details reply for a rejected request.
///
/// Parameters: `status` — 400, 413 or 431. Returns: the reply.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `rejection(431)`.
fn rejection(status: Int) -> Reply {
  api.problem(
    status,
    http.reason(status),
    "the request is malformed or too large",
    None,
  )
}

/// Answer a rejected request and log it.
///
/// Parameters: `context` — the server context; `connection` — the
/// socket; `status` — 400, 413 or 431. Returns: Nil. Errors: none (a
/// failed send is ignored, the connection closes anyway).
/// Side Effects: sends the reply with `Connection: close`; logs at debug.
/// Complexity: O(1). Thread Safety: socket owner. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `reject(context, connection, 400)`.
fn reject(context: Context, connection: Socket, status: Int) -> Nil {
  let _ =
    socket.send(connection, http.format_reply(rejection(status), False, True))
  log.event(
    context.log,
    log.Debug,
    "request rejected",
    Some(int.to_string(status)),
  )
}

/// Serve the requests of one admitted connection.
///
/// Parameters: `context` — the server context; `connection` — the
/// socket. Returns: Nil when the connection is to be closed. Errors: none.
/// Side Effects: reads and writes the socket; calls the contract process
/// and the tracker; logs. Complexity: O(n) in the input.
/// Thread Safety: socket owner. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `serve(context, connection)`.
fn serve(context: Context, connection: Socket) -> Nil {
  let reader =
    http.new_reader(fn() { socket.receive(connection, idle_timeout_ms) })
  serve_requests(context, connection, reader)
}

/// Serve requests from a reader until the connection ends.
///
/// Description: reads a head and its body; asks the contract process for
/// the reply; logs it at debug level with the trace context; sends it
/// with `Connection: close` when the request or a stop asks for it.
/// Malformed requests are answered 400, 413 or 431 and end the
/// connection. Tells the tracker when a request starts and when its reply
/// is sent.
/// Business Justification: persistent connections let the successor
/// service reuse one connection for its many calls (CLAUDE.md 3, step 7).
/// Parameters: `context` — the server context; `connection` — the socket;
/// `reader` — the buffered input. Returns: Nil when the connection is to
/// be closed. Errors: none. Side Effects: as `serve`.
/// Complexity: O(n). Thread Safety: socket owner. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `serve_requests(context, connection, reader)`.
fn serve_requests(context: Context, connection: Socket, reader: Reader) -> Nil {
  case http.read_head(reader) {
    #(http.Ended, _) -> Nil
    #(http.Rejected(status), _) -> reject(context, connection, status)
    #(http.Head(head), reader) -> {
      tracker.busy(context.tracker)
      case http.read_body(reader, head.headers) {
        #(Error(status), _) -> reject(context, connection, status)
        #(Ok(Nil), reader) -> {
          let path = case string.split_once(head.target, "?") {
            Ok(#(path, _)) -> path
            Error(Nil) -> head.target
          }
          let reply = api.answer(context.contract, head.method, path)
          let allowed = tracker.keep(context.tracker)
          let keep = http.keep_alive(head.minor, head.headers) && allowed
          let context_trace =
            trace.parse(
              option.from_result(dict.get(head.headers, "traceparent")),
            )
          log.write(
            context.log,
            log.Debug,
            "request answered",
            option.map(context_trace, fn(t) { t.trace_id }),
            option.map(context_trace, fn(t) { t.span_id }),
            Some(
              head.method
              <> " "
              <> path
              <> " -> "
              <> int.to_string(reply.status),
            ),
          )
          let sent =
            socket.send(
              connection,
              http.format_reply(reply, head.method == "HEAD", !keep),
            )
          tracker.idle(context.tracker)
          case sent && keep {
            True -> serve_requests(context, connection, reader)
            False -> Nil
          }
        }
      }
    }
  }
}
