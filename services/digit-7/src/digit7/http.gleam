//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/http.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         HTTP/1.1 message framing (RFC 9112) for the digit
////                  server: buffered line reading with a size budget,
////                  request heads, bodies by Content-Length or chunked,
////                  persistent connections and reply formatting.
//// Related Docs:    RFC 9112, contracts/http/digit.yaml, ADR-0028, ADR-0029
////
//// HTTP/1.1 framing of the digit-7 service.
////
//// The rules and limits are those of `digit-6` (ADR-0028): heads up to
//// `max_head` bytes (431 above), bodies up to `max_body` bytes read and
//// discarded (413 above, 400 for ambiguous framing), keep-alive unless
//// the client or HTTP/1.0 says otherwise. Everything here is pure except
//// the `receive` function of a `Reader`, so the tests drive it with
//// prepared input.

import digit7/api.{type Reply}
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Largest request head (request line and header fields), in bytes; a
/// larger one is answered 431.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
pub const max_head = 8192

/// Largest request body read and discarded, in bytes; a larger one is
/// answered 413.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub const max_body = 65_536

/// A buffered reader of one connection's input.
///
/// Description: `receive` returns the next bytes, or `<<>>` at the end
/// of input (peer closed, idle timeout, error); after that the reader is
/// `ended` and never calls it again.
/// Thread Safety: an immutable value; `receive` must be called by the
/// socket's owner. Owner: AEC. Since: digit-7 0.1.0.
pub type Reader {
  /// The unread bytes, the end flag and the input function.
  Reader(buffer: BitArray, ended: Bool, receive: fn() -> BitArray)
}

/// Why a line could not be read.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type LineError {
  /// The input ended before the line feed.
  LineClosed
  /// The line, or the bytes buffered without a line feed, exceed the
  /// budget.
  TooLarge
}

/// A parsed request head.
///
/// Description: header names are lower-case; repeated fields are joined
/// with `, ` (RFC 9110, 5.3).
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type RequestHead {
  /// Method, request target, HTTP minor version (`0` or `1`) and fields.
  RequestHead(
    method: String,
    target: String,
    minor: String,
    headers: Dict(String, String),
  )
}

/// The outcome of reading a request head.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type HeadOutcome {
  /// A complete head.
  Head(RequestHead)
  /// A head to answer with this status (400 or 431) before closing.
  Rejected(Int)
  /// The input ended before a request started; close silently.
  Ended
}

/// A reader over an input function, with an empty buffer.
///
/// Parameters: `receive` — returns the next bytes or `<<>>` at the end.
/// Returns: the reader. Errors: none. Side Effects: none.
/// Complexity: O(1). Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `new_reader(fn() { socket.receive(s, 10_000) })`.
pub fn new_reader(receive: fn() -> BitArray) -> Reader {
  Reader(buffer: <<>>, ended: False, receive:)
}

/// A reader over fixed input, ended after it.
///
/// Business Justification: the unit tests frame prepared requests without
/// a socket.
/// Parameters: `input` — every byte the peer sends. Returns: the reader.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `from_bytes(<<"GET /value HTTP/1.1\r\n\r\n":utf8>>)`.
pub fn from_bytes(input: BitArray) -> Reader {
  Reader(buffer: input, ended: True, receive: fn() { <<>> })
}

/// Append the next input to the buffer.
///
/// Parameters: `reader` — the reader. Returns: the reader with more
/// bytes. Errors: `Nil` at the end of input. Side Effects: calls
/// `receive` (reads the socket). Complexity: O(n) in the buffer.
/// Thread Safety: socket owner. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `fill(reader)`.
fn fill(reader: Reader) -> Result(Reader, Nil) {
  case reader.ended {
    True -> Error(Nil)
    False ->
      case reader.receive() {
        <<>> -> Error(Nil)
        chunk ->
          Ok(Reader(..reader, buffer: bit_array.append(reader.buffer, chunk)))
      }
  }
}

/// Index of the first line feed in a binary.
///
/// Parameters: `bytes` — the binary; `index` — the index of its first
/// byte (0 at the top call). Returns: the index of the first byte 10.
/// Errors: `Nil` when there is none. Side Effects: none.
/// Complexity: O(n). Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `line_feed(<<"ab\n":utf8>>, 0) == Ok(2)`.
fn line_feed(bytes: BitArray, index: Int) -> Result(Int, Nil) {
  case bytes {
    <<10, _:bytes>> -> Ok(index)
    <<_, rest:bytes>> -> line_feed(rest, index + 1)
    _ -> Error(Nil)
  }
}

/// Encodings of `unicode:characters_to_binary/2`.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
type Encoding {
  /// The Erlang atom `latin1`: one byte is one character.
  Latin1
}

/// `unicode:characters_to_binary/2`: bytes read as Latin-1, as UTF-8.
///
/// Parameters: `bytes` — any bytes; `encoding` — `latin1`. Returns: the
/// text; every byte maps to one character. Errors: none for Latin-1.
/// Side Effects: none. Complexity: O(n). Thread Safety: pure. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `latin1_to_string(<<65>>, Latin1) == "A"`.
@external(erlang, "unicode", "characters_to_binary")
fn latin1_to_string(bytes: BitArray, encoding: Encoding) -> String

/// The text of a line without its trailing carriage return.
///
/// Parameters: `bytes` — the line without the line feed. Returns: the
/// text, each byte one character (Latin-1), so any byte sequence is a
/// valid string. Errors: none. Side Effects: none. Complexity: O(n).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `line_text(<<"a\r":utf8>>) == "a"`.
fn line_text(bytes: BitArray) -> String {
  let size = bit_array.byte_size(bytes)
  let bytes = case bit_array.slice(bytes, size - 1, 1) {
    Ok(<<13>>) -> result.unwrap(bit_array.slice(bytes, 0, size - 1), bytes)
    _ -> bytes
  }
  latin1_to_string(bytes, Latin1)
}

/// Read one line within a byte budget.
///
/// Description: the line ends at a line feed; a preceding carriage return
/// is dropped. The line feed counts against the budget.
/// Business Justification: a client cannot make the service buffer more
/// than the budget for one head.
/// Parameters: `reader` — the reader; `budget` — the bytes the line may
/// use, line feed included. Returns: the text, the bytes used and the
/// reader after the line.
/// Errors: `TooLarge` when the line or the bytes buffered without a line
/// feed exceed the budget; `LineClosed` at the end of input.
/// Side Effects: reads the socket as needed. Complexity: O(n · k) for k
/// reads. Thread Safety: socket owner. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `read_line(from_bytes(<<"a\r\n":utf8>>), 10)`.
pub fn read_line(
  reader: Reader,
  budget: Int,
) -> Result(#(String, Int, Reader), LineError) {
  let available = bit_array.byte_size(reader.buffer)
  case line_feed(reader.buffer, 0) {
    Ok(end) if end + 1 > budget -> Error(TooLarge)
    Ok(end) -> {
      let line = result.unwrap(bit_array.slice(reader.buffer, 0, end), <<>>)
      let rest =
        result.unwrap(
          bit_array.slice(reader.buffer, end + 1, available - end - 1),
          <<>>,
        )
      Ok(#(line_text(line), end + 1, Reader(..reader, buffer: rest)))
    }
    Error(Nil) if available > budget -> Error(TooLarge)
    Error(Nil) ->
      case fill(reader) {
        Ok(reader) -> read_line(reader, budget)
        Error(Nil) -> Error(LineClosed)
      }
  }
}

/// Discard a number of bytes.
///
/// Parameters: `reader` — the reader; `count` — bytes to discard, 0 or
/// more. Returns: the reader after them. Errors: `Nil` when the input
/// ends first. Side Effects: reads the socket as needed.
/// Complexity: O(count). Thread Safety: socket owner. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `skip(from_bytes(<<1, 2, 3>>), 2)`.
pub fn skip(reader: Reader, count: Int) -> Result(Reader, Nil) {
  let available = bit_array.byte_size(reader.buffer)
  case available >= count {
    True ->
      Ok(
        Reader(
          ..reader,
          buffer: result.unwrap(
            bit_array.slice(reader.buffer, count, available - count),
            <<>>,
          ),
        ),
      )
    False ->
      Reader(..reader, buffer: <<>>)
      |> fill
      |> result.try(skip(_, count - available))
  }
}

/// Whether a code point is a `tchar` of RFC 9110 (5.6.2).
///
/// Parameters: `codepoint` — the code point as an integer. Returns: True
/// for ASCII letters, digits and ``!#$%&'*+-.^_`|~``. Errors: none.
/// Side Effects: none. Complexity: O(1). Thread Safety: pure. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `is_token(0x41) == True`.
fn is_token(codepoint: Int) -> Bool {
  { codepoint >= 0x30 && codepoint <= 0x39 }
  || { codepoint >= 0x41 && codepoint <= 0x5A }
  || { codepoint >= 0x61 && codepoint <= 0x7A }
  || string.contains("!#$%&'*+-.^_`|~", string_of(codepoint))
}

/// The one-character string of a code point (empty when invalid).
///
/// Parameters: `codepoint` — the code point. Returns: the string.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `string_of(0x21) == "!"`.
fn string_of(codepoint: Int) -> String {
  case string.utf_codepoint(codepoint) {
    Ok(value) -> string.from_utf_codepoints([value])
    Error(Nil) -> ""
  }
}

/// The code points of a string as integers.
///
/// Parameters: `text` — the string. Returns: the integers. Errors: none.
/// Side Effects: none. Complexity: O(n). Thread Safety: pure. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `codepoints("A") == [65]`.
fn codepoints(text: String) -> List(Int) {
  text |> string.to_utf_codepoints |> list.map(string.utf_codepoint_to_int)
}

/// Whether a non-empty string consists of `tchar`s only.
///
/// Parameters: `text` — the string. Returns: True for a token.
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `is_token_text("GET")`.
fn is_token_text(text: String) -> Bool {
  text != "" && list.all(codepoints(text), is_token)
}

/// Parse a request line: method SP request-target SP HTTP-version.
///
/// Description: the method must be a token, the target non-empty without
/// spaces or control characters, the version `HTTP/1.0` or `HTTP/1.1`.
/// Business Justification: a malformed request is answered 400 instead of
/// being guessed at.
/// Parameters: `line` — the line without CRLF. Returns: the method, the
/// target and the minor version (`0` or `1`). Errors: `Nil` for a
/// malformed line. Side Effects: none. Complexity: O(n).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `parse_request_line("GET /next HTTP/1.1")`.
pub fn parse_request_line(
  line: String,
) -> Result(#(String, String, String), Nil) {
  case string.split(line, " ") {
    [method, target, version] ->
      case
        is_token_text(method)
        && target != ""
        && list.all(codepoints(target), fn(c) { c > 32 && c != 127 })
      {
        False -> Error(Nil)
        True ->
          case version {
            "HTTP/1.0" -> Ok(#(method, target, "0"))
            "HTTP/1.1" -> Ok(#(method, target, "1"))
            _ -> Error(Nil)
          }
      }
    _ -> Error(Nil)
  }
}

/// Drop spaces and tabs at both ends of a field value.
///
/// Parameters: `text` — the value. Returns: the trimmed value.
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `trim_ows(" a\t") == "a"`.
fn trim_ows(text: String) -> String {
  text
  |> string.to_graphemes
  |> list.drop_while(is_ows)
  |> list.reverse
  |> list.drop_while(is_ows)
  |> list.reverse
  |> string.concat
}

/// Whether a grapheme is optional whitespace (space or tab).
///
/// Parameters: `grapheme` — one grapheme. Returns: True for SP or HTAB.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `is_ows("\t") == True`.
fn is_ows(grapheme: String) -> Bool {
  grapheme == " " || grapheme == "\t"
}

/// Parse a header field line: field-name ":" OWS field-value OWS.
///
/// Parameters: `line` — the line without CRLF. Returns: the lower-case
/// name and the trimmed value. Errors: `Nil` when there is no colon or
/// the name is not a token. Side Effects: none. Complexity: O(n).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `parse_header("Connection: close") == Ok(#("connection", "close"))`.
pub fn parse_header(line: String) -> Result(#(String, String), Nil) {
  case string.split_once(line, ":") {
    Ok(#(name, value)) ->
      case is_token_text(name) {
        True -> Ok(#(string.lowercase(name), trim_ows(value)))
        False -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

/// Whether a comma-separated field value lists a token.
///
/// Parameters: `value` — the field value, if present; `token` — the
/// lower-case token. Returns: True when listed (case-insensitive).
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `has_token(Some("Keep-Alive"), "keep-alive") == True`.
fn has_token(value: Option(String), token: String) -> Bool {
  case value {
    None -> False
    Some(text) ->
      text
      |> string.lowercase
      |> string.split(",")
      |> list.any(fn(item) { trim_ows(item) == token })
  }
}

/// Whether the connection stays open after this request.
///
/// Description: HTTP/1.1 keeps it unless the request says `Connection:
/// close`; HTTP/1.0 closes it unless the request says `Connection:
/// keep-alive` (RFC 9112, 9.3).
/// Parameters: `minor` — `0` or `1`; `headers` — the request fields.
/// Returns: True to keep the connection. Errors: none. Side Effects: none.
/// Complexity: O(n). Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `keep_alive("1", dict.new()) == True`.
pub fn keep_alive(minor: String, headers: Dict(String, String)) -> Bool {
  let connection = option.from_result(dict.get(headers, "connection"))
  case minor {
    "1" -> !has_token(connection, "close")
    _ -> has_token(connection, "keep-alive")
  }
}

/// The reason phrase of a status code the service sends.
///
/// Parameters: `status` — the code. Returns: the phrase, empty for others.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `reason(431)`.
pub fn reason(status: Int) -> String {
  case status {
    200 -> "OK"
    400 -> "Bad Request"
    404 -> "Not Found"
    405 -> "Method Not Allowed"
    413 -> "Content Too Large"
    431 -> "Request Header Fields Too Large"
    503 -> "Service Unavailable"
    _ -> ""
  }
}

/// `calendar:universal_time/0`: the UTC date and time.
///
/// Parameters: none. Returns: `#(#(year, month, day), #(hour, minute,
/// second))`. Errors: none. Side Effects: reads the clock.
/// Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `universal_time()`.
@external(erlang, "calendar", "universal_time")
fn universal_time() -> #(#(Int, Int, Int), #(Int, Int, Int))

/// `calendar:day_of_the_week/1`: 1 (Monday) to 7 (Sunday).
///
/// Parameters: `date` — `#(year, month, day)`. Returns: the weekday.
/// Errors: none for a valid date. Side Effects: none. Complexity: O(1).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `day_of_the_week(#(2026, 10, 22)) == 4`.
@external(erlang, "calendar", "day_of_the_week")
fn day_of_the_week(date: #(Int, Int, Int)) -> Int

/// A number with at least two digits.
///
/// Parameters: `value` — 0 or more. Returns: e.g. `07`. Errors: none.
/// Side Effects: none. Complexity: O(1). Thread Safety: pure. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `two_digits(7) == "07"`.
fn two_digits(value: Int) -> String {
  string.pad_start(int.to_string(value), to: 2, with: "0")
}

/// The current time as an HTTP date (IMF-fixdate, RFC 9110 5.6.7).
///
/// Parameters: none. Returns: e.g. `Thu, 22 Oct 2026 19:52:01 GMT`.
/// Errors: none. Side Effects: reads the clock. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `http_date()`.
pub fn http_date() -> String {
  let #(#(year, month, day), #(hour, minute, second)) = universal_time()
  let weekday = case day_of_the_week(#(year, month, day)) {
    1 -> "Mon"
    2 -> "Tue"
    3 -> "Wed"
    4 -> "Thu"
    5 -> "Fri"
    6 -> "Sat"
    _ -> "Sun"
  }
  let month_name = case month {
    1 -> "Jan"
    2 -> "Feb"
    3 -> "Mar"
    4 -> "Apr"
    5 -> "May"
    6 -> "Jun"
    7 -> "Jul"
    8 -> "Aug"
    9 -> "Sep"
    10 -> "Oct"
    11 -> "Nov"
    _ -> "Dec"
  }
  weekday
  <> ", "
  <> two_digits(day)
  <> " "
  <> month_name
  <> " "
  <> int.to_string(year)
  <> " "
  <> two_digits(hour)
  <> ":"
  <> two_digits(minute)
  <> ":"
  <> two_digits(second)
  <> " GMT"
}

/// Format a reply as HTTP/1.1 bytes.
///
/// Description: status line, Date, Content-Type, Content-Length, Allow
/// (when set) and `Connection: close` (when closing); the body is left
/// out for HEAD, Content-Length still gives its size.
/// Parameters: `reply` — the reply; `head` — True for a HEAD request;
/// `close` — True when the connection closes after it. Returns: the
/// bytes. Errors: none. Side Effects: reads the clock. Complexity: O(n).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `format_reply(reply, False, True)`.
pub fn format_reply(reply: Reply, head: Bool, close: Bool) -> BitArray {
  let body = bit_array.from_string(reply.body)
  let text =
    "HTTP/1.1 "
    <> int.to_string(reply.status)
    <> " "
    <> reason(reply.status)
    <> "\r\nDate: "
    <> http_date()
    <> "\r\nContent-Type: "
    <> reply.content_type
    <> "\r\nContent-Length: "
    <> int.to_string(bit_array.byte_size(body))
    <> "\r\n"
    <> case reply.allow {
      Some(allow) -> "Allow: " <> allow <> "\r\n"
      None -> ""
    }
    <> case close {
      True -> "Connection: close\r\n"
      False -> ""
    }
    <> "\r\n"
  case head {
    True -> bit_array.from_string(text)
    False -> bit_array.append(bit_array.from_string(text), body)
  }
}

/// Read the request line, skipping empty lines before it (RFC 9112, 2.2).
///
/// Parameters: `reader` — the reader; `budget` — bytes left for the head.
/// Returns: the line, the budget left and the reader. Errors: as
/// `read_line`. Side Effects: reads the socket. Complexity: O(n).
/// Thread Safety: socket owner. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `request_line(reader, max_head)`.
fn request_line(
  reader: Reader,
  budget: Int,
) -> Result(#(String, Int, Reader), LineError) {
  use #(line, used, reader) <- result.try(read_line(reader, budget))
  case line {
    "" -> request_line(reader, budget - used)
    _ -> Ok(#(line, budget - used, reader))
  }
}

/// Read header field lines up to the empty line.
///
/// Parameters: `reader` — the reader; `budget` — bytes left for the head;
/// `headers` — the fields read so far. Returns: the outcome and the
/// reader; a missing or oversized field is `Rejected(431)` or
/// `Rejected(400)`. Errors: none (failures are outcomes).
/// Side Effects: reads the socket. Complexity: O(n).
/// Thread Safety: socket owner. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `read_fields(reader, 8000, dict.new())`.
fn read_fields(
  reader: Reader,
  budget: Int,
  headers: Dict(String, String),
) -> #(Result(Dict(String, String), Int), Reader) {
  case read_line(reader, budget) {
    Error(TooLarge) -> #(Error(431), reader)
    Error(LineClosed) -> #(Error(400), reader)
    Ok(#("", _, reader)) -> #(Ok(headers), reader)
    Ok(#(line, used, reader)) ->
      case parse_header(line) {
        Error(Nil) -> #(Error(400), reader)
        Ok(#(name, value)) -> {
          let joined = case dict.get(headers, name) {
            Ok(previous) -> previous <> ", " <> value
            Error(Nil) -> value
          }
          read_fields(reader, budget - used, dict.insert(headers, name, joined))
        }
      }
  }
}

/// Read a request head.
///
/// Description: skips empty lines before the request line; the whole
/// head, those lines included, may use at most `max_head` bytes.
/// Business Justification: bounded input per request keeps the memory
/// of the service flat under any client.
/// Parameters: `reader` — the reader. Returns: `Head`, `Rejected(431)`
/// for an oversized head, `Rejected(400)` for a malformed head or one cut
/// short after the request line, or `Ended` when the input ended before
/// a request line; and the reader after the head. Errors: none.
/// Side Effects: reads the socket. Complexity: O(n).
/// Thread Safety: socket owner. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `read_head(from_bytes(<<"GET / HTTP/1.1\r\n\r\n":utf8>>))`.
pub fn read_head(reader: Reader) -> #(HeadOutcome, Reader) {
  case request_line(reader, max_head) {
    Error(TooLarge) -> #(Rejected(431), reader)
    Error(LineClosed) -> #(Ended, reader)
    Ok(#(line, budget, reader)) ->
      case parse_request_line(line) {
        Error(Nil) -> #(Rejected(400), reader)
        Ok(#(method, target, minor)) ->
          case read_fields(reader, budget, dict.new()) {
            #(Error(status), reader) -> #(Rejected(status), reader)
            #(Ok(headers), reader) -> #(
              Head(RequestHead(method:, target:, minor:, headers:)),
              reader,
            )
          }
      }
  }
}

/// Whether a text is 1 to `max` characters of the given digit set.
///
/// Parameters: `text` — the text; `max` — longest allowed length;
/// `digits` — the allowed characters. Returns: True when it qualifies.
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `all_digits("12", 9, "0123456789") == True`.
fn all_digits(text: String, max: Int, digits: String) -> Bool {
  let length = string.length(text)
  length >= 1
  && length <= max
  && list.all(string.to_graphemes(text), string.contains(digits, _))
}

/// The leading hexadecimal digits of a chunk-size line.
///
/// Parameters: `line` — the line (chunk extensions may follow).
/// Returns: the digits, possibly empty. Errors: none. Side Effects: none.
/// Complexity: O(n). Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `chunk_size_digits("1a;x=y") == "1a"`.
fn chunk_size_digits(line: String) -> String {
  line
  |> string.to_graphemes
  |> list.take_while(string.contains("0123456789abcdefABCDEF", _))
  |> string.concat
}

/// Read and discard the chunks of a chunked body, then its trailer.
///
/// Parameters: `reader` — the reader; `total` — chunk bytes so far.
/// Returns: `Ok(Nil)` or the status to answer (400, 413) and the reader.
/// Errors: none (failures are statuses). Side Effects: reads the socket.
/// Complexity: O(n). Thread Safety: socket owner. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `read_chunks(reader, 0)`.
fn read_chunks(reader: Reader, total: Int) -> #(Result(Nil, Int), Reader) {
  case read_line(reader, max_head) {
    Error(_) -> #(Error(400), reader)
    Ok(#(line, _, reader)) -> {
      let size = chunk_size_digits(line)
      case all_digits(size, 8, "0123456789abcdefABCDEF") {
        False -> #(Error(400), reader)
        True -> {
          let count = result.unwrap(int.base_parse(size, 16), 0)
          case total + count > max_body, count {
            True, _ -> #(Error(413), reader)
            False, 0 -> read_trailer(reader)
            False, _ ->
              case skip(reader, count) {
                Error(Nil) -> #(Error(400), reader)
                Ok(reader) ->
                  case read_line(reader, 2) {
                    Ok(#("", _, reader)) -> read_chunks(reader, total + count)
                    _ -> #(Error(400), reader)
                  }
              }
          }
        }
      }
    }
  }
}

/// Read and discard the trailer fields of a chunked body.
///
/// Parameters: `reader` — the reader. Returns: `Ok(Nil)` at the empty
/// line, `Error(400)` when the input ends or a line is too long, and the
/// reader. Errors: none. Side Effects: reads the socket.
/// Complexity: O(n). Thread Safety: socket owner. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `read_trailer(reader)`.
fn read_trailer(reader: Reader) -> #(Result(Nil, Int), Reader) {
  case read_line(reader, max_head) {
    Error(_) -> #(Error(400), reader)
    Ok(#("", _, reader)) -> #(Ok(Nil), reader)
    Ok(#(_, _, reader)) -> read_trailer(reader)
  }
}

/// Read and discard the request body.
///
/// Description: by `Transfer-Encoding: chunked` (trailer fields are read
/// and ignored) or by `Content-Length`; no body without either. A request
/// with both, or with another transfer coding, is 400.
/// Business Justification: the contract has no request bodies, but a body
/// sent anyway must not be mistaken for the next request.
/// Parameters: `reader` — the reader after the head; `headers` — the
/// request fields. Returns: `Ok(Nil)` or the status to answer (400, 413)
/// before closing, and the reader. Errors: none.
/// Side Effects: reads the socket. Complexity: O(n).
/// Thread Safety: socket owner. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `read_body(reader, head.headers)`.
pub fn read_body(
  reader: Reader,
  headers: Dict(String, String),
) -> #(Result(Nil, Int), Reader) {
  case
    dict.get(headers, "transfer-encoding"),
    dict.get(headers, "content-length")
  {
    Ok(coding), Error(Nil) ->
      case string.lowercase(coding) {
        "chunked" -> read_chunks(reader, 0)
        _ -> #(Error(400), reader)
      }
    Ok(_), Ok(_) -> #(Error(400), reader)
    Error(Nil), Error(Nil) -> #(Ok(Nil), reader)
    Error(Nil), Ok(length) ->
      case all_digits(length, 9, "0123456789") {
        False -> #(Error(400), reader)
        True -> {
          let count = result.unwrap(int.parse(length), 0)
          case count > max_body {
            True -> #(Error(413), reader)
            False ->
              case skip(reader, count) {
                Ok(reader) -> #(Ok(Nil), reader)
                Error(Nil) -> #(Error(400), reader)
              }
          }
        }
      }
  }
}
