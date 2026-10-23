//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/socket.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Typed bindings to Erlang's gen_tcp and inet for the
////                  HTTP server: listen, accept, receive, send, shutdown
////                  and close of TCP sockets in passive binary mode.
//// Related Docs:    https://www.erlang.org/doc/apps/kernel/gen_tcp.html,
////                  ADR-0029
////
//// TCP sockets of the digit-7 HTTP server.
////
//// The bindings are Gleam `@external` declarations: no Erlang source is
//// added to the service. Option values are Gleam constructors whose
//// Erlang form is the option term (`Active(False)` is `{active, false}`).
//// Every socket is passive (`{active, false}`): data is read only by an
//// explicit `receive`, so a slow handler never queues messages.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/atom

/// A TCP socket (an Erlang `gen_tcp` socket).
///
/// Thread Safety: owned by the process that accepted it; the socket is
/// closed when that process exits. Owner: Arithmetic Excellence Center
/// (AEC). Since: digit-7 0.1.0.
pub type Socket

/// Options of `gen_tcp:listen/2`; accepted sockets inherit them.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
type ListenOption {
  /// `binary`: data is received as binaries.
  Binary
  /// `{active, false}`: passive mode, data only through `recv`.
  Active(Bool)
  /// `{reuseaddr, true}`: the port can be bound again right after a stop.
  Reuseaddr(Bool)
  /// `{backlog, N}`: pending connections queued by the kernel.
  Backlog(Int)
  /// `{nodelay, true}`: replies are sent without Nagle's delay.
  Nodelay(Bool)
  /// `{send_timeout, Ms}`: a send to a client that does not read fails.
  SendTimeout(Int)
  /// `{send_timeout_close, true}`: such a socket is closed.
  SendTimeoutClose(Bool)
  /// `{buffer, Bytes}`: the user-level receive buffer, the most one
  /// `recv` returns.
  Buffer(Int)
}

/// Directions of `gen_tcp:shutdown/2`.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
type Direction {
  /// The Erlang atom `write`: no more data is sent (FIN).
  Write
}

/// Milliseconds a send may block before the socket is closed.
///
/// Owner: AEC. Since: digit-7 0.1.0.
const send_timeout_ms = 10_000

/// Most bytes one receive returns.
///
/// Description: without it the driver's buffer grows to whatever the
/// client has sent, and a flood of large heads leaves the memory
/// allocators fragmented; 16 KiB covers a whole head of 8 KiB.
/// Owner: AEC. Since: digit-7 0.1.0.
const receive_buffer_bytes = 16_384

/// `gen_tcp:listen/2`.
///
/// Parameters: `port` — the port; `options` — listen options.
/// Returns: the listening socket or the reason. Errors: as the result
/// says. Side Effects: binds the port. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `gen_listen(8080, [Binary])`.
@external(erlang, "gen_tcp", "listen")
fn gen_listen(port: Int, options: List(ListenOption)) -> Result(Socket, Dynamic)

/// `gen_tcp:accept/1`: wait for the next connection.
///
/// Parameters: `listener` — the listening socket. Returns: the connection
/// socket, owned by the caller, or the reason (`closed` after `close`).
/// Errors: as the result says. Side Effects: blocks until a client
/// connects. Complexity: O(1). Thread Safety: safe. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `gen_accept(listener)`.
@external(erlang, "gen_tcp", "accept")
fn gen_accept(listener: Socket) -> Result(Socket, Dynamic)

/// `gen_tcp:recv/3` with length 0: the bytes available, at least one.
///
/// Parameters: `socket` — the socket; `length` — 0; `timeout` — in ms.
/// Returns: the bytes or the reason (`closed`, `timeout`, …).
/// Errors: as the result says. Side Effects: reads the socket.
/// Complexity: O(n). Thread Safety: owning process. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `gen_recv(socket, 0, 10_000)`.
@external(erlang, "gen_tcp", "recv")
fn gen_recv(
  socket: Socket,
  length: Int,
  timeout: Int,
) -> Result(BitArray, Dynamic)

/// `gen_tcp:send/2`.
///
/// Parameters: `socket` — the socket; `data` — the bytes. Returns: `ok`
/// or `{error, Reason}`. Errors: as the result says. Side Effects: writes
/// to the socket. Complexity: O(n). Thread Safety: owning process.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `gen_send(socket, <<>>)`.
@external(erlang, "gen_tcp", "send")
fn gen_send(socket: Socket, data: BitArray) -> Dynamic

/// `gen_tcp:shutdown/2`.
///
/// Parameters: `socket` — the socket; `direction` — `write`. Returns: `ok`
/// or `{error, Reason}`. Errors: as the result says. Side Effects: sends
/// FIN. Complexity: O(1). Thread Safety: owning process. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `gen_shutdown(socket, Write)`.
@external(erlang, "gen_tcp", "shutdown")
fn gen_shutdown(socket: Socket, direction: Direction) -> Dynamic

/// `gen_tcp:close/1`.
///
/// Parameters: `socket` — the socket. Returns: `ok`. Errors: none.
/// Side Effects: closes the socket. Complexity: O(1). Thread Safety: any
/// process. Owner: AEC. Since: digit-7 0.1.0. Example: `gen_close(socket)`.
@external(erlang, "gen_tcp", "close")
fn gen_close(socket: Socket) -> Dynamic

/// `inet:port/1`: the local port of a socket.
///
/// Parameters: `socket` — the socket. Returns: the port or the reason.
/// Errors: as the result says. Side Effects: none. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `inet_port(listener)`.
@external(erlang, "inet", "port")
fn inet_port(socket: Socket) -> Result(Int, Dynamic)

/// The reason of a failed socket call as text.
///
/// Description: an atom reason (`closed`, `eaddrinuse`, `timeout`) as its
/// name, any other term as `unknown`.
/// Parameters: `reason` — the Erlang reason term. Returns: its name.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `reason(closed) == "closed"`.
pub fn reason(reason: Dynamic) -> String {
  case decode.run(reason, atom.decoder()) {
    Ok(name) -> atom.to_string(name)
    Error(_) -> "unknown"
  }
}

/// Listen on a TCP port on every IPv4 address.
///
/// Business Justification: the digit contract is served on port 8080 in
/// the container (CLAUDE.md 6.1); the tests listen on port 0.
/// Parameters: `port` — 0..65535 (0: any free port); `backlog` — pending
/// connections queued by the kernel. Returns: the listening socket, owned
/// by the caller. Errors: the reason as text (`eaddrinuse`, `eacces`).
/// Side Effects: binds the port. Complexity: O(1). Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `listen(8080, 256)`.
pub fn listen(port: Int, backlog: Int) -> Result(Socket, String) {
  case
    gen_listen(port, [
      Binary,
      Active(False),
      Reuseaddr(True),
      Backlog(backlog),
      Nodelay(True),
      SendTimeout(send_timeout_ms),
      SendTimeoutClose(True),
      Buffer(receive_buffer_bytes),
    ])
  {
    Ok(socket) -> Ok(socket)
    Error(error) -> Error(reason(error))
  }
}

/// Wait for the next connection.
///
/// Parameters: `listener` — the listening socket. Returns: the connection
/// socket, owned by the caller. Errors: the reason as text (`closed` once
/// the listener is closed). Side Effects: blocks. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `accept(listener)`.
pub fn accept(listener: Socket) -> Result(Socket, String) {
  case gen_accept(listener) {
    Ok(socket) -> Ok(socket)
    Error(error) -> Error(reason(error))
  }
}

/// Receive the bytes available, waiting up to a timeout.
///
/// Parameters: `socket` — the socket; `timeout_ms` — the wait.
/// Returns: one or more bytes, or `<<>>` when the peer closed, the wait
/// expired or the socket failed (the callers treat all three as the end
/// of input). Errors: none. Side Effects: reads the socket.
/// Complexity: O(n). Thread Safety: owning process. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `receive(socket, 10_000)`.
pub fn receive(socket: Socket, timeout_ms: Int) -> BitArray {
  case gen_recv(socket, 0, timeout_ms) {
    Ok(bytes) -> bytes
    Error(_) -> <<>>
  }
}

/// Send bytes.
///
/// Parameters: `socket` — the socket; `data` — the bytes. Returns: True
/// when sent, False when the peer is gone or the send timed out.
/// Errors: none. Side Effects: writes to the socket. Complexity: O(n).
/// Thread Safety: owning process. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `send(socket, <<"HTTP/1.1 200 OK\r\n":utf8>>)`.
pub fn send(socket: Socket, data: BitArray) -> Bool {
  gen_send(socket, data) == atom.to_dynamic(atom.create("ok"))
}

/// Stop sending (FIN); the socket can still receive.
///
/// Parameters: `socket` — the socket. Returns: Nil. Errors: none (a
/// failure is ignored). Side Effects: sends FIN. Complexity: O(1).
/// Thread Safety: owning process. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `shutdown_write(socket)`.
pub fn shutdown_write(socket: Socket) -> Nil {
  let _ = gen_shutdown(socket, Write)
  Nil
}

/// Close a socket.
///
/// Parameters: `socket` — the socket. Returns: Nil. Errors: none.
/// Side Effects: closes the socket; a pending `accept` on a closed
/// listener returns `closed`. Complexity: O(1). Thread Safety: any
/// process. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `close(socket)`.
pub fn close(socket: Socket) -> Nil {
  let _ = gen_close(socket)
  Nil
}

/// The local port of a socket.
///
/// Parameters: `socket` — the socket. Returns: the port, 0 when it
/// cannot be read. Errors: none. Side Effects: none. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `port(listener) == 8080`.
pub fn port(socket: Socket) -> Int {
  case inet_port(socket) {
    Ok(port) -> port
    Error(_) -> 0
  }
}
