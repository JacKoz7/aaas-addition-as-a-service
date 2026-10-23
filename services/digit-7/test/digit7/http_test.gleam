//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          test/digit7/http_test.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Unit tests of the HTTP/1.1 framing
////                  (src/digit7/http.gleam) on prepared input, whole and
////                  split into pieces.
//// Related Docs:    RFC 9112, ADR-0028, ADR-0029
////
//// HTTP framing tests of the digit-7 service.

import digit7/api
import digit7/http
import gleam/bit_array
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// A reader that receives the given pieces one by one, then ends.
///
/// Parameters: `pieces` — the input in the order received. Returns: the
/// reader. Errors: none. Side Effects: queues the pieces in a subject of
/// the calling process. Complexity: O(n). Thread Safety: caller only.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
/// Example: `pieces(["GET / HT", "TP/1.1\r\n\r\n"])`.
pub fn pieces(input: List(String)) -> http.Reader {
  let queue = process.new_subject()
  list.each(input, fn(piece) {
    process.send(queue, bit_array.from_string(piece))
  })
  http.new_reader(fn() { result.unwrap(process.receive(queue, 0), <<>>) })
}

/// The head of a prepared request.
///
/// Parameters: `text` — the whole input. Returns: the outcome.
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `head_of("GET / HTTP/1.1\r\n\r\n")`.
fn head_of(text: String) -> http.HeadOutcome {
  http.read_head(http.from_bytes(bit_array.from_string(text))).0
}

/// Lines end at LF with an optional CR; the line feed counts.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn read_line_test() {
  let reader = http.from_bytes(<<"ab\r\ncd\nrest":utf8>>)
  let assert Ok(#("ab", 4, reader)) = http.read_line(reader, 10)
  let assert Ok(#("cd", 3, reader)) = http.read_line(reader, 3)
  assert http.read_line(reader, 10) == Error(http.LineClosed)
}

/// A line over the budget is TooLarge, with or without a line feed.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn read_line_budget_test() {
  assert http.read_line(http.from_bytes(<<"abcd\n":utf8>>), 4)
    == Error(http.TooLarge)
  assert http.read_line(http.from_bytes(<<"abcde":utf8>>), 4)
    == Error(http.TooLarge)
}

/// Lines split across receives are joined.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn read_line_pieces_test() {
  let reader = pieces(["G", "ET /va", "lue HTTP/1.1\r", "\n"])
  let assert Ok(#("GET /value HTTP/1.1", 21, _)) = http.read_line(reader, 100)
}

/// Bytes above 127 are read as Latin-1 characters.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn read_line_latin1_test() {
  let assert Ok(#(line, 3, _)) =
    http.read_line(http.from_bytes(<<0xE9, 0xFF, 10>>), 10)
  assert line == "éÿ"
}

/// `skip` discards bytes across receives and fails at the end of input.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn skip_test() {
  let assert Ok(reader) = http.skip(pieces(["abc", "def", "g\n"]), 5)
  let assert Ok(#("fg", 3, _)) = http.read_line(reader, 10)
  assert http.skip(http.from_bytes(<<"ab":utf8>>), 3) == Error(Nil)
}

/// Request lines need a token method, a target and HTTP/1.0 or 1.1.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn parse_request_line_test() {
  assert http.parse_request_line("GET /next HTTP/1.1")
    == Ok(#("GET", "/next", "1"))
  assert http.parse_request_line("BREW /x?y=1 HTTP/1.0")
    == Ok(#("BREW", "/x?y=1", "0"))
  assert http.parse_request_line("GET /next HTTP/2.0") == Error(Nil)
  assert http.parse_request_line("GET  /next HTTP/1.1") == Error(Nil)
  assert http.parse_request_line("GET /next") == Error(Nil)
  assert http.parse_request_line("G(T /next HTTP/1.1") == Error(Nil)
  assert http.parse_request_line("GET /a\u{7F} HTTP/1.1") == Error(Nil)
  assert http.parse_request_line("PRI * HTTP/2.0") == Error(Nil)
}

/// Header fields are lower-cased and trimmed of spaces and tabs.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn parse_header_test() {
  assert http.parse_header("Connection: \tclose \t")
    == Ok(#("connection", "close"))
  assert http.parse_header("X-Empty:") == Ok(#("x-empty", ""))
  assert http.parse_header("no colon") == Error(Nil)
  assert http.parse_header(" Host: x") == Error(Nil)
  assert http.parse_header(": x") == Error(Nil)
}

/// HTTP/1.1 keeps the connection unless asked to close; HTTP/1.0 closes
/// it unless asked to keep it.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn keep_alive_test() {
  let close = dict.from_list([#("connection", "Upgrade, Close")])
  let keep = dict.from_list([#("connection", "keep-alive")])
  assert http.keep_alive("1", dict.new())
  assert !http.keep_alive("1", close)
  assert !http.keep_alive("0", dict.new())
  assert http.keep_alive("0", keep)
}

/// A head with fields, empty lines before it and repeated fields.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn read_head_test() {
  let assert http.Head(head) =
    head_of(
      "\r\n\r\nGET /value?x=1 HTTP/1.1\r\nHost: digit-7\r\n"
      <> "Accept: a\r\naccept: b\r\n\r\n",
    )
  assert head.method == "GET"
  assert head.target == "/value?x=1"
  assert head.minor == "1"
  assert dict.get(head.headers, "host") == Ok("digit-7")
  assert dict.get(head.headers, "accept") == Ok("a, b")
}

/// Malformed heads are 400; no input is Ended.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn read_head_malformed_test() {
  assert head_of("") == http.Ended
  assert head_of("\r\n") == http.Ended
  assert head_of("GARBAGE\r\n\r\n") == http.Rejected(400)
  assert head_of("GET / HTTP/1.1\r\nbad field\r\n\r\n") == http.Rejected(400)
  assert head_of("GET / HTTP/1.1\r\nHost: x\r\n") == http.Rejected(400)
  assert head_of("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n") == http.Rejected(400)
}

/// A head over max_head bytes is 431; one at the limit is accepted.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn read_head_too_large_test() {
  let start = "GET / HTTP/1.1\r\n"
  let filler = fn(size) { "X: " <> string.repeat("a", size - 5) <> "\r\n" }
  let exact = start <> filler(http.max_head - 16 - 2) <> "\r\n"
  assert string.byte_size(exact) == http.max_head
  let assert http.Head(_) = head_of(exact)
  let over = start <> filler(http.max_head - 16 - 1) <> "\r\n"
  assert head_of(over) == http.Rejected(431)
  assert head_of(string.repeat("a", 9000)) == http.Rejected(431)
}

/// A body of Content-Length bytes is skipped, leaving the next request.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn content_length_body_test() {
  let reader =
    pieces([
      "POST /value HTTP/1.1\r\nContent-Length: 10\r\n\r\n01234",
      "56789GET /value HTTP/1.1\r\n\r\n",
    ])
  let assert #(http.Head(head), reader) = http.read_head(reader)
  let assert #(Ok(Nil), reader) = http.read_body(reader, head.headers)
  let assert #(http.Head(next), _) = http.read_head(reader)
  assert next.method == "GET"
}

/// Content-Length must be 1..9 digits, at most max_body, and complete.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn content_length_errors_test() {
  let body = fn(value, rest) {
    http.read_body(
      http.from_bytes(bit_array.from_string(rest)),
      dict.from_list([#("content-length", value)]),
    ).0
  }
  assert body("70000", "") == Error(413)
  assert body("65536", string.repeat("a", 65_536)) == Ok(Nil)
  assert body("-1", "") == Error(400)
  assert body("1 2", "") == Error(400)
  assert body("5", "abc") == Error(400)
  assert body("", "") == Error(400)
}

/// A chunked body with an extension and a trailer is skipped.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn chunked_body_test() {
  let reader =
    pieces([
      "POST /value HTTP/1.1\r\nTransfer-Encoding: Chunked\r\n\r\n",
      "5;ext=1\r\nhel",
      "lo\r\nA\r\n0123456789\r\n0\r\nTrailer: x\r\n\r\nGET / HTTP/1.1\r\n\r\n",
    ])
  let assert #(http.Head(head), reader) = http.read_head(reader)
  let assert #(Ok(Nil), reader) = http.read_body(reader, head.headers)
  let assert #(http.Head(next), _) = http.read_head(reader)
  assert next.target == "/"
}

/// Chunked framing errors: size, CRLF, total, other codings, both headers.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn chunked_errors_test() {
  let chunked = fn(rest) {
    http.read_body(
      http.from_bytes(bit_array.from_string(rest)),
      dict.from_list([#("transfer-encoding", "chunked")]),
    ).0
  }
  assert chunked("zz\r\n") == Error(400)
  assert chunked("123456789\r\n") == Error(400)
  assert chunked("3\r\nabcX\r\n0\r\n\r\n") == Error(400)
  assert chunked("10001\r\n") == Error(413)
  assert chunked("8000\r\n" <> string.repeat("a", 32_768) <> "\r\n8001\r\n")
    == Error(413)
  assert chunked("0\r\n") == Error(400)
  assert http.read_body(
      http.from_bytes(<<>>),
      dict.from_list([#("transfer-encoding", "gzip")]),
    ).0
    == Error(400)
  assert http.read_body(
      http.from_bytes(<<>>),
      dict.from_list([
        #("transfer-encoding", "chunked"),
        #("content-length", "0"),
      ]),
    ).0
    == Error(400)
}

/// Replies carry Date, Content-Type, Content-Length, Allow and Connection.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn format_reply_test() {
  let reply = api.problem(405, "Method Not Allowed", "x", Some("GET"))
  let assert Ok(text) =
    bit_array.to_string(http.format_reply(reply, False, True))
  assert string.starts_with(text, "HTTP/1.1 405 Method Not Allowed\r\nDate: ")
  assert string.contains(
    text,
    " GMT\r\nContent-Type: application/problem+json\r\n",
  )
  assert string.contains(
    text,
    "\r\nContent-Length: "
      <> string.inspect(string.byte_size(reply.body))
      <> "\r\nAllow: GET\r\nConnection: close\r\n\r\n",
  )
  assert string.ends_with(text, reply.body)
}

/// HEAD replies keep Content-Length but leave the body out.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn format_head_reply_test() {
  let reply = api.Reply(200, api.json_type, "{\"a\":1}", None)
  let assert Ok(text) =
    bit_array.to_string(http.format_reply(reply, True, False))
  assert string.ends_with(text, "Content-Length: 7\r\n\r\n")
  assert !string.contains(text, "Connection")
}

/// Every status the service sends has its reason phrase.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn reason_test() {
  assert http.reason(413) == "Content Too Large"
  assert http.reason(431) == "Request Header Fields Too Large"
  assert http.reason(999) == ""
}

/// HTTP dates have the IMF-fixdate shape.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn http_date_test() {
  let date = http.http_date()
  assert string.length(date) == 29
  assert string.ends_with(date, " GMT")
  assert string.slice(date, 3, 2) == ", "
}
