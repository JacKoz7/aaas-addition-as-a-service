//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          test/digit7/server_test.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Tests of the HTTP server (src/digit7/server.gleam)
////                  over real TCP connections on a free local port.
//// Related Docs:    RFC 9112, ADR-0028, ADR-0029
////
//// Transport tests of the digit-7 service: persistent connections,
//// rejected requests, HTTP/1.0 and the graceful stop.

import digit7/api
import digit7/api_test
import digit7/server
import digit7/socket.{type Socket}
import digit7/tracker
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/erlang/charlist.{type Charlist}
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Options of `gen_tcp:connect/3`.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
type ConnectOption {
  /// The Erlang atom `binary`.
  Binary
  /// `{active, false}`.
  Active(Bool)
}

/// `gen_tcp:connect/3`.
///
/// Parameters: `host` — the address; `port` — the port; `options` — the
/// options. Returns: the socket or the reason. Errors: as the result
/// says. Side Effects: connects. Complexity: O(1). Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `gen_connect(h, 8080, [])`.
@external(erlang, "gen_tcp", "connect")
fn gen_connect(
  host: Charlist,
  port: Int,
  options: List(ConnectOption),
) -> Result(Socket, Dynamic)

/// `gen_tcp:recv/3`.
///
/// Parameters: `socket`, `length` (0: what is available), `timeout`.
/// Returns: the bytes or the reason. Errors: as the result says.
/// Side Effects: reads. Complexity: O(n). Thread Safety: owner.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `gen_recv(s, 0, 1000)`.
@external(erlang, "gen_tcp", "recv")
fn gen_recv(
  socket: Socket,
  length: Int,
  timeout: Int,
) -> Result(BitArray, Dynamic)

/// A server on a free port over a fresh contract process.
///
/// Parameters: none. Returns: the server. Errors: panics when it cannot
/// start (a test failure). Side Effects: binds a port, spawns processes.
/// Complexity: O(1). Thread Safety: caller only. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `start()`.
fn start() -> server.Server {
  let state = api_test.state(7)
  let assert Ok(contract) = api.start(state)
  let assert Ok(running) = server.start(0, contract, state.log)
  running
}

/// Connect to a server.
///
/// Parameters: `running` — the server. Returns: the client socket.
/// Errors: panics when the connection fails. Side Effects: connects.
/// Complexity: O(1). Thread Safety: caller only. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `connect(running)`.
fn connect(running: server.Server) -> Socket {
  let assert Ok(client) =
    gen_connect(charlist.from_string("127.0.0.1"), running.port, [
      Binary,
      Active(False),
    ])
  client
}

/// Send text on a client socket.
///
/// Parameters: `client` — the socket; `text` — the bytes as text.
/// Returns: Nil. Errors: panics when the send fails. Side Effects: sends.
/// Complexity: O(n). Thread Safety: owner. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `send(client, "GET / HTTP/1.1\r\n\r\n")`.
fn send(client: Socket, text: String) -> Nil {
  let assert True = socket.send(client, bit_array.from_string(text))
  Nil
}

/// Read one complete reply (head and Content-Length bytes of body).
///
/// Parameters: `client` — the socket; `buffer` — bytes read so far.
/// Returns: the reply text, or what arrived before the connection closed
/// or went silent for 2 s. Errors: none. Side Effects: reads.
/// Complexity: O(n). Thread Safety: owner. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `reply(client, "")`.
fn reply(client: Socket, buffer: String) -> String {
  let complete = case string.split_once(buffer, "\r\n\r\n") {
    Error(Nil) -> False
    Ok(#(head, body)) ->
      case string.split_once(head, "Content-Length: ") {
        Error(Nil) -> True
        Ok(#(_, rest)) -> {
          let length =
            rest
            |> string.split("\r\n")
            |> list.first
            |> result.try(int.parse)
            |> result.unwrap(0)
          string.byte_size(body) >= length
        }
      }
  }
  case complete {
    True -> buffer
    False ->
      case gen_recv(client, 0, 2000) {
        Ok(bytes) ->
          reply(client, buffer <> result.unwrap(bit_array.to_string(bytes), ""))
        Error(_) -> buffer
      }
  }
}

/// Whether the server closed the connection (EOF within 1 s).
///
/// Parameters: `client` — the socket. Returns: True on EOF or reset.
/// Errors: none. Side Effects: reads. Complexity: O(1).
/// Thread Safety: owner. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `closed(client)`.
fn closed(client: Socket) -> Bool {
  case gen_recv(client, 0, 1000) {
    Error(reason) -> socket.reason(reason) != "timeout"
    Ok(_) -> False
  }
}

/// Two requests on one persistent connection, the second with a query.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn keep_alive_test() {
  let running = start()
  let client = connect(running)
  send(client, "GET /value HTTP/1.1\r\nHost: x\r\n\r\n")
  let first = reply(client, "")
  assert string.starts_with(first, "HTTP/1.1 200 OK\r\n")
  assert string.ends_with(first, "{\"digit\":7,\"value\":7}")
  assert !string.contains(first, "Connection: close")
  send(client, "GET /next?debug=1 HTTP/1.1\r\n\r\n")
  assert string.ends_with(
    reply(client, ""),
    "{\"digit\":7,\"next\":8,\"carry\":false}",
  )
  server.stop(running)
}

/// HTTP/1.0 replies close the connection.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn http_1_0_test() {
  let running = start()
  let client = connect(running)
  send(client, "GET /health HTTP/1.0\r\n\r\n")
  let text = reply(client, "")
  assert string.contains(text, "\r\nConnection: close\r\n")
  assert closed(client)
  server.stop(running)
}

/// Oversized heads, oversized bodies and garbage are rejected and closed.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn rejections_test() {
  let running = start()
  let cases = [
    #("GET / HTTP/1.1\r\nX: " <> string.repeat("a", 9000) <> "\r\n\r\n", "431"),
    #("POST /value HTTP/1.1\r\nContent-Length: 70000\r\n\r\n", "413"),
    #("garbage\r\n\r\n", "400"),
  ]
  list.each(cases, fn(item) {
    let client = connect(running)
    send(client, item.0)
    let text = reply(client, "")
    assert string.starts_with(text, "HTTP/1.1 " <> item.1 <> " ")
    assert string.contains(text, "application/problem+json")
    assert string.contains(text, "Connection: close")
    assert closed(client)
  })
  server.stop(running)
}

/// A chunked body is skipped and the connection keeps serving.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn chunked_then_get_test() {
  let running = start()
  let client = connect(running)
  send(
    client,
    "POST /value HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n",
  )
  assert string.starts_with(reply(client, ""), "HTTP/1.1 405 ")
  send(client, "GET /value HTTP/1.1\r\n\r\n")
  assert string.starts_with(reply(client, ""), "HTTP/1.1 200 ")
  server.stop(running)
}

/// HEAD answers 405 without a body; the pipelined GET that follows is
/// answered on the same connection.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn head_test() {
  let running = start()
  let client = connect(running)
  send(client, "HEAD /value HTTP/1.1\r\n\r\nGET /value HTTP/1.1\r\n\r\n")
  let text = read_until(client, "", "{\"digit\":7,\"value\":7}")
  assert string.starts_with(text, "HTTP/1.1 405 ")
  assert string.contains(text, "\r\nAllow: GET\r\n\r\nHTTP/1.1 200 OK\r\n")
  server.stop(running)
}

/// Read until the input ends with a text.
///
/// Parameters: `client` — the socket; `buffer` — bytes so far; `suffix`
/// — the expected end. Returns: the text read, or what arrived before the
/// connection closed or went silent for 2 s. Errors: none.
/// Side Effects: reads. Complexity: O(n). Thread Safety: owner.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `read_until(client, "", "}")`.
fn read_until(client: Socket, buffer: String, suffix: String) -> String {
  case string.ends_with(buffer, suffix) {
    True -> buffer
    False ->
      case gen_recv(client, 0, 2000) {
        Ok(bytes) ->
          read_until(
            client,
            buffer <> result.unwrap(bit_array.to_string(bytes), ""),
            suffix,
          )
        Error(_) -> buffer
      }
  }
}

/// A stop closes idle connections at once and frees the port.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn stop_test() {
  let running = start()
  let client = connect(running)
  send(client, "GET /value HTTP/1.1\r\n\r\n")
  let _ = reply(client, "")
  server.stop(running)
  assert closed(client)
  assert tracker.count(running.tracker) == #(0, 0)
  let assert Error(_) =
    gen_connect(charlist.from_string("127.0.0.1"), running.port, [
      Binary,
      Active(False),
    ])
}
