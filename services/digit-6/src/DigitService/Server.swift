// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          src/DigitService/Server.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Minimal HTTP/1.1 server on POSIX sockets: one thread per
//                  connection, persistent connections, bounded request
//                  heads and bodies, a connection cap and a graceful stop.
// Related Docs:    services/digit-6/README.md, contracts/http/digit.yaml,
//                  ADR-0028

import Synchronization

#if canImport(Glibc)
  import Glibc
#elseif canImport(Darwin)
  import Darwin
#endif

/// Largest request head (request line and header fields), in bytes; a
/// larger head is answered 431.
///
/// Owner: AEC. Since: digit-6 0.1.0.
public let maxHead = 8192

/// Largest request body read and discarded, in bytes; a larger one is
/// answered 413 without being read.
///
/// Owner: AEC. Since: digit-6 0.1.0.
public let maxBody = 65536

/// Most connections served at once; further ones are closed on accept.
///
/// Owner: AEC. Since: digit-6 0.1.0.
public let maxConnections = 256

/// Seconds a connection may stay silent, between requests or within one,
/// before it is closed.
///
/// Owner: AEC. Since: digit-6 0.1.0.
public let idleTimeoutSeconds = 10

/// Seconds the server waits for running requests after a stop.
///
/// Owner: AEC. Since: digit-6 0.1.0.
let drainTimeoutSeconds = 5

/// Milliseconds unread input is still read and discarded after the last
/// reply, before the socket is closed.
///
/// Owner: AEC. Since: digit-6 0.1.0.
let lingerMilliseconds = 200

/// Most bytes discarded after the last reply; a client still sending more
/// is cut off.
///
/// Owner: AEC. Since: digit-6 0.1.0.
let lingerBytes = 16384

/// Stack size of a connection thread, in bytes: the handler is shallow, so
/// 256 threads stay within a few MiB of resident memory.
///
/// Owner: AEC. Since: digit-6 0.1.0.
let threadStackSize = 256 * 1024

/// Reason phrases of the statuses the service sends.
///
/// Owner: AEC. Since: digit-6 0.1.0.
let reasons: [Int: String] = [
  200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed",
  413: "Content Too Large", 431: "Request Header Fields Too Large", 503: "Service Unavailable",
]

/// The two directions of a client connection, as the transport uses them.
///
/// Business Justification: the transport is tested with an in-memory
/// double instead of a socket.
///
/// Thread Safety: one thread per connection.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public protocol Connection: AnyObject {
  /// Receive up to `max` bytes.
  ///
  /// - Parameter max: Most bytes to return.
  /// - Returns: The bytes received; empty at the end of the input, on an
  ///   error or after the receive timeout.
  ///
  /// Errors: none (empty). Side Effects: reads the connection.
  /// Complexity: O(n). Thread Safety: one thread. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `let chunk = connection.receive(max: 4096)`.
  func receive(max: Int) -> [UInt8]

  /// Send all bytes.
  ///
  /// - Parameter bytes: The bytes.
  /// - Returns: True when every byte was sent.
  ///
  /// Errors: none (false). Side Effects: writes the connection.
  /// Complexity: O(n). Thread Safety: one thread. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `connection.send(bytes)`.
  func send(_ bytes: [UInt8]) -> Bool
}

/// Outcome of reading one line of a request.
///
/// Thread Safety: a value type; safe. Owner: AEC. Since: digit-6 0.1.0.
public enum LineError: Error, Equatable {
  /// The input ended, failed or stayed silent past the receive timeout.
  case closed
  /// The line is longer than the bytes still allowed.
  case tooLarge
}

/// Buffered reader of a connection's input.
///
/// Description: keeps the bytes received but not yet consumed. After the
/// end of the input, a failure or a timeout, every read reports the end.
///
/// Business Justification: requests may arrive split across packets or
/// several in one packet (pipelining).
///
/// Thread Safety: one thread per connection.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public final class InputReader {
  /// The connection.
  private let connection: Connection
  /// Bytes received; those before `position` are consumed.
  private var buffer: [UInt8] = []
  /// Index of the first unconsumed byte of `buffer`.
  private var position = 0
  /// True once the input ended, failed or timed out.
  private var ended = false

  /// Read from `connection`.
  ///
  /// - Parameter connection: The connection.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// one thread. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `let reader = InputReader(connection)`.
  public init(_ connection: Connection) {
    self.connection = connection
  }

  /// Number of bytes received but not consumed.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// one thread. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `reader.available`.
  var available: Int { buffer.count - position }

  /// Receive the next chunk of input and append it to the buffer.
  ///
  /// - Returns: False at the end of the input, on a failure or a timeout.
  ///
  /// Errors: none. Side Effects: reads the connection. Complexity: O(n) in
  /// the unconsumed bytes. Thread Safety: one thread. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `guard fill() else { return .closed }`.
  private func fill() -> Bool {
    guard !ended else { return false }
    let chunk = connection.receive(max: 16384)
    guard !chunk.isEmpty else {
      ended = true
      return false
    }
    buffer = Array(buffer[position...]) + chunk
    position = 0
    return true
  }

  /// Read one line.
  ///
  /// Description: lines end with LF, optionally preceded by CR, which is
  /// removed. `budget` is the number of bytes the line may take, its line
  /// ending included.
  ///
  /// Business Justification: bounds the memory a client can make the
  /// service hold.
  ///
  /// - Parameter budget: Bytes still allowed.
  /// - Returns: The line (ISO 8859-1 decoded) and the bytes it took, or
  ///   the error.
  ///
  /// Errors: ``LineError`` values. Side Effects: reads the connection.
  /// Complexity: O(n). Thread Safety: one thread. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `let result = reader.readLine(budget: 8192)`.
  public func readLine(budget: Int) -> Result<(line: String, used: Int), LineError> {
    var searched = position
    while true {
      if let end = buffer[searched...].firstIndex(of: 10) {
        let used = end - position + 1
        guard used <= budget else { return .failure(.tooLarge) }
        var stop = end
        if stop > position && buffer[stop - 1] == 13 {
          stop -= 1
        }
        let line = String(buffer[position..<stop].map { Character(Unicode.Scalar($0)) })
        position = end + 1
        return .success((line, used))
      }
      guard available <= budget else { return .failure(.tooLarge) }
      let scanned = available
      guard fill() else { return .failure(.closed) }
      searched = scanned
    }
  }

  /// Read and discard `count` bytes.
  ///
  /// - Parameter count: Bytes to skip.
  /// - Returns: True when all bytes were read.
  ///
  /// Errors: none (false when the input ends early). Side Effects: reads
  /// the connection. Complexity: O(n). Thread Safety: one thread.
  /// Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `reader.skip(10)`.
  public func skip(_ count: Int) -> Bool {
    var left = count
    while true {
      let take = min(left, available)
      position += take
      left -= take
      if left == 0 { return true }
      guard fill() else { return false }
    }
  }
}

/// A parsed request head.
///
/// Thread Safety: a value type; safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public struct RequestHead: Equatable {
  /// Method, as received.
  public let method: String
  /// Request target (path and query).
  public let target: String
  /// Minor HTTP version, "0" or "1".
  public let minor: String
  /// Header fields by lower-case name; repeated fields joined by commas.
  public let headers: [String: String]
}

/// Whether a byte is an RFC 9110 token character (tchar).
///
/// - Parameter byte: The byte.
/// - Returns: True for a token character.
///
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
/// safe. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `isToken(UInt8(ascii: "G")) == true`.
func isToken(_ byte: UInt8) -> Bool {
  switch byte {
  case 48...57, 65...90, 97...122: return true
  default: return Array("!#$%&'*+-.^_`|~".utf8).contains(byte)
  }
}

/// Parse a request line.
///
/// Description: the line must be method SP request-target SP
/// HTTP-version, where the method is a token (RFC 9110 tchar), the target
/// has no spaces or control characters and the version is HTTP/1.0 or
/// HTTP/1.1. The trailing CR LF must already be removed.
///
/// Business Justification: a malformed request is answered 400 instead of
/// being guessed at.
///
/// - Parameter line: Request line without CR LF.
/// - Returns: Method, target and minor version, or nil when invalid.
///
/// Errors: none (nil). Side Effects: none. Complexity: O(n).
/// Thread Safety: safe (pure). Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-6 0.1.0.
///
/// Example: `parseRequestLine("GET /next HTTP/1.1")`.
///
/// See Also: ``parseHeader(_:)``.
public func parseRequestLine(_ line: String) -> (method: String, target: String, minor: String)? {
  let parts = line.split(separator: " ", omittingEmptySubsequences: false)
  guard parts.count == 3, !parts[0].isEmpty, parts[0].utf8.allSatisfy(isToken),
    !parts[1].isEmpty, parts[1].utf8.allSatisfy({ $0 > 32 && $0 != 127 }),
    parts[2] == "HTTP/1.0" || parts[2] == "HTTP/1.1"
  else { return nil }
  return (String(parts[0]), String(parts[1]), String(parts[2].suffix(1)))
}

/// Parse a header field line.
///
/// Description: name ":" OWS value OWS; the name is a token and is
/// returned in lower case. Obsolete line folding (a line starting with a
/// space) is rejected.
///
/// Business Justification: header fields decide the body length, the
/// persistence of the connection and the trace context.
///
/// - Parameter line: Header line without CR LF.
/// - Returns: The lower-case name and the value, or nil when invalid.
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
/// safe. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `parseHeader("Content-Length: 5")`.
public func parseHeader(_ line: String) -> (String, String)? {
  guard let colon = line.firstIndex(of: ":") else { return nil }
  let name = line[..<colon]
  guard !name.isEmpty, name.utf8.allSatisfy(isToken) else { return nil }
  let value = line[line.index(after: colon)...].drop { $0 == " " || $0 == "\t" }
  var end = value.endIndex
  while end > value.startIndex, [" ", "\t"].contains(value[value.index(before: end)]) {
    end = value.index(before: end)
  }
  return (name.lowercased(), String(value[..<end]))
}

/// Whether a comma-separated header value contains a token.
///
/// - Parameters:
///   - value: Header value, nil when absent.
///   - token: Lower-case token.
/// - Returns: True when present (case-insensitive).
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
/// safe. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `hasToken("keep-alive, Close", "close") == true`.
func hasToken(_ value: String?, _ token: String) -> Bool {
  guard let value else { return false }
  return value.lowercased().split(separator: ",").contains {
    $0.trimmingCharacters(" \t") == token
  }
}

extension Substring {
  /// The substring without leading and trailing characters of `set`.
  ///
  /// - Parameter set: Characters to remove.
  /// - Returns: The trimmed text.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
  /// safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `" a ".dropFirst(0).trimmingCharacters(" ") == "a"`.
  func trimmingCharacters(_ set: String) -> String {
    String(drop { set.contains($0) }.reversed().drop { set.contains($0) }.reversed())
  }
}

/// Whether the connection stays open after the reply.
///
/// Description: HTTP/1.1 keeps it unless the request says Connection:
/// close; HTTP/1.0 keeps it only with Connection: keep-alive.
///
/// Business Justification: callers reuse connections, which saves a TCP
/// handshake per digit call.
///
/// - Parameters:
///   - minor: Minor HTTP version, "0" or "1".
///   - headers: Header fields by lower-case name.
/// - Returns: True to keep the connection.
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
/// safe. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `keepAlive("1", [:]) == true`.
public func keepAlive(_ minor: String, _ headers: [String: String]) -> Bool {
  minor == "1"
    ? !hasToken(headers["connection"], "close") : hasToken(headers["connection"], "keep-alive")
}

/// The current date in the IMF-fixdate format of the Date header.
///
/// - Returns: For example `Mon, 19 Oct 2026 12:00:00 GMT`.
///
/// Errors: none. Side Effects: reads the clock. Complexity: O(1).
/// Thread Safety: safe (`gmtime_r`). Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `httpDate()`.
func httpDate() -> String {
  var seconds = time(nil)
  var parts = tm()
  gmtime_r(&seconds, &parts)
  var buffer = [CChar](repeating: 0, count: 40)
  let length = strftime(&buffer, buffer.count, "%a, %d %b %Y %H:%M:%S GMT", &parts)
  return String(decoding: buffer[0..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// Serialise a reply.
///
/// Description: status line, Date, Content-Type, Content-Length, Allow
/// when the reply has one and Connection: close when the connection ends;
/// the body is left out for HEAD.
///
/// Business Justification: one place produces the bytes of every answer.
///
/// - Parameters:
///   - reply: The reply.
///   - head: True for a HEAD request.
///   - close: True when the connection is closed after the reply.
/// - Returns: The response bytes.
///
/// Errors: none. Side Effects: reads the clock. Complexity: O(n) in the
/// body. Thread Safety: safe. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `formatReply(reply, head: false, close: false)`.
public func formatReply(_ reply: Reply, head: Bool, close: Bool) -> [UInt8] {
  let body = Array(reply.body.utf8)
  var text = "HTTP/1.1 \(reply.status) \(reasons[reply.status] ?? "")\r\n"
  text += "Date: \(httpDate())\r\nContent-Type: \(reply.contentType)\r\n"
  text += "Content-Length: \(body.count)\r\n"
  if let allow = reply.allow {
    text += "Allow: \(allow)\r\n"
  }
  if close {
    text += "Connection: close\r\n"
  }
  text += "\r\n"
  return Array(text.utf8) + (head ? [] : body)
}

/// Read a request head.
///
/// Description: skips empty lines before the request line (RFC 9112,
/// 2.2), then reads header fields up to the empty line. Repeated fields
/// are joined with a comma.
///
/// - Parameter reader: The connection's input.
/// - Returns: The head, or the error status: nil for a clean end (the
///   client closed or went silent before the request line was complete),
///   400 for a malformed head or one cut short after the request line,
///   431 for a head above ``maxHead``.
///
/// Errors: none. Side Effects: reads the connection. Complexity: O(n).
/// Thread Safety: one thread. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `let (head, status) = readHead(reader)`.
func readHead(_ reader: InputReader) -> (RequestHead?, Int?) {
  var budget = maxHead
  var line = ""
  repeat {
    switch reader.readLine(budget: budget) {
    case .failure(let error): return (nil, error == .tooLarge ? 431 : nil)
    case .success(let result):
      budget -= result.used
      line = result.line
    }
  } while line.isEmpty
  guard let request = parseRequestLine(line) else { return (nil, 400) }
  var headers: [String: String] = [:]
  while true {
    switch reader.readLine(budget: budget) {
    case .failure(let error): return (nil, error == .tooLarge ? 431 : 400)
    case .success(let result):
      budget -= result.used
      if result.line.isEmpty {
        return (
          RequestHead(
            method: request.method, target: request.target, minor: request.minor,
            headers: headers), nil
        )
      }
      guard let (name, value) = parseHeader(result.line) else { return (nil, 400) }
      headers[name] = headers[name].map { $0 + ", " + value } ?? value
    }
  }
}

/// Read and discard the request body.
///
/// Description: Content-Length bodies up to ``maxBody`` are skipped;
/// chunked bodies are skipped chunk by chunk with the same total limit
/// (trailer fields are read and ignored). A request with both
/// Content-Length and Transfer-Encoding, another transfer coding or an
/// invalid length is malformed (RFC 9112, 6.1 and 6.3).
///
/// Business Justification: the contract has no request bodies, but a body
/// sent anyway must not be mistaken for the next request.
///
/// - Parameters:
///   - reader: The connection's input.
///   - headers: Header fields by lower-case name.
/// - Returns: Nil when the body was skipped, otherwise the error status:
///   400 for a malformed or truncated body, 413 for one above ``maxBody``.
///
/// Errors: none. Side Effects: reads the connection. Complexity: O(n).
/// Thread Safety: one thread. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `let status = readBody(reader, head.headers)`.
func readBody(_ reader: InputReader, _ headers: [String: String]) -> Int? {
  let length = headers["content-length"]
  if let coding = headers["transfer-encoding"] {
    guard length == nil, coding.lowercased() == "chunked" else { return 400 }
    var total = 0
    while true {
      guard case .success(let result) = reader.readLine(budget: maxHead) else { return 400 }
      let size = result.line.prefix { $0.isHexDigit }
      guard (1...8).contains(size.count), let count = Int(size, radix: 16) else { return 400 }
      total += count
      if total > maxBody { return 413 }
      if count == 0 { break }
      guard reader.skip(count), case .success(let end) = reader.readLine(budget: 2),
        end.line.isEmpty
      else { return 400 }
    }
    while true {
      guard case .success(let trailer) = reader.readLine(budget: maxHead) else { return 400 }
      if trailer.line.isEmpty { return nil }
    }
  }
  guard let length else { return nil }
  guard (1...9).contains(length.count), length.utf8.allSatisfy({ (48...57).contains($0) }),
    let count = Int(length)
  else { return 400 }
  if count > maxBody { return 413 }
  return reader.skip(count) ? nil : 400
}

/// The problem details reply for a rejected request.
///
/// - Parameter status: 400, 413 or 431.
/// - Returns: The reply.
///
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
/// safe. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `rejection(431)`.
func rejection(_ status: Int) -> Reply {
  problem(status, reasons[status] ?? "", "the request is malformed or too large")
}

/// Serve the requests of one connection until it ends.
///
/// Description: reads a head, skips the body, asks `handler` for the
/// reply, logs it at debug level with the trace context and sends it;
/// repeats while the connection is persistent and `stopping` returns
/// false. Malformed requests are answered 400, 413 or 431 with problem
/// details and end the connection. `busy` is called with true when a
/// request starts and with false when it is answered.
///
/// Business Justification: the transport of the digit contract.
///
/// - Parameters:
///   - connection: The connection.
///   - handler: Returns the reply for a method and a path.
///   - stopping: Returns true once the server stops.
///   - busy: Request start and end notifications.
///   - log: Logger.
///
/// Errors: none (write failures end the connection). Side Effects: reads
/// and writes the connection; calls `handler`; logs. Complexity: O(n) per
/// request. Thread Safety: one thread per connection. Owner: AEC.
/// Since: digit-6 0.1.0.
///
/// Example: `serveConnection(connection, handler: api.handle, stopping: { false }, busy: { _ in }, log: log)`.
///
/// See Also: ``Api/handle(method:path:)``.
public func serveConnection(
  _ connection: Connection, handler: (String, String) -> Reply, stopping: () -> Bool,
  busy: (Bool) -> Void, log: Logger
) {
  let reader = InputReader(connection)
  while true {
    let (head, headStatus) = readHead(reader)
    guard let head else {
      if let headStatus {
        _ = connection.send(formatReply(rejection(headStatus), head: false, close: true))
        log.write(.debug, "request rejected", detail: "\(headStatus)")
      }
      return
    }
    busy(true)
    if let bodyStatus = readBody(reader, head.headers) {
      _ = connection.send(formatReply(rejection(bodyStatus), head: false, close: true))
      log.write(.debug, "request rejected", detail: "\(bodyStatus)")
      return
    }
    let path = String(head.target.prefix { $0 != "?" })
    let reply = handler(head.method, path)
    let keep = keepAlive(head.minor, head.headers) && !stopping()
    let trace = TraceContext.parse(head.headers["traceparent"])
    log.write(
      .debug, "request answered", traceId: trace?.traceId, spanId: trace?.spanId,
      detail: "\(head.method) \(path) -> \(reply.status)")
    let sent = connection.send(formatReply(reply, head: head.method == "HEAD", close: !keep))
    busy(false)
    if !sent || !keep { return }
  }
}

/// A TCP connection of the server.
///
/// Thread Safety: used by its connection thread; the server may only call
/// `shutdown` on its descriptor from another thread.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
final class SocketConnection: Connection {
  /// The socket descriptor.
  let fd: Int32

  /// Wrap an accepted socket and set its options.
  ///
  /// Description: TCP_NODELAY, a receive timeout of
  /// ``idleTimeoutSeconds``, and no SIGPIPE on writes (MSG_NOSIGNAL).
  ///
  /// - Parameter fd: The accepted socket.
  ///
  /// Errors: none (options are best effort). Side Effects: sets socket
  /// options. Complexity: O(1). Thread Safety: one thread. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `SocketConnection(fd: client)`.
  init(fd: Int32) {
    self.fd = fd
    var one: Int32 = 1
    setsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
    setTimeout(milliseconds: idleTimeoutSeconds * 1000)
  }

  /// Set the receive timeout of the socket.
  ///
  /// - Parameter milliseconds: Timeout.
  ///
  /// Errors: none. Side Effects: sets SO_RCVTIMEO. Complexity: O(1).
  /// Thread Safety: one thread. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `setTimeout(milliseconds: 200)`.
  func setTimeout(milliseconds: Int) {
    var value = timeval(
      tv_sec: time_t(milliseconds / 1000), tv_usec: suseconds_t(milliseconds % 1000) * 1000)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
  }

  /// Receive up to `max` bytes (see ``Connection/receive(max:)``).
  ///
  /// - Parameter max: Most bytes to return.
  /// - Returns: The bytes; empty at the end, on an error or a timeout.
  ///
  /// Errors: none. Side Effects: reads the socket. Complexity: O(n).
  /// Thread Safety: one thread. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `connection.receive(max: 4096)`.
  func receive(max: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: max)
    let count = recv(fd, &bytes, max, 0)
    return count > 0 ? Array(bytes[0..<count]) : []
  }

  /// Send all bytes (see ``Connection/send(_:)``).
  ///
  /// - Parameter bytes: The bytes.
  /// - Returns: True when every byte was sent.
  ///
  /// Errors: none. Side Effects: writes the socket. Complexity: O(n).
  /// Thread Safety: one thread. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `connection.send(bytes)`.
  func send(_ bytes: [UInt8]) -> Bool {
    var offset = 0
    while offset < bytes.count {
      let count = bytes[offset...].withUnsafeBytes {
        Glibc.send(fd, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL))
      }
      guard count > 0 else { return false }
      offset += count
    }
    return true
  }

  /// Close with a linger: stop writing, discard input for up to
  /// ``lingerMilliseconds`` or ``lingerBytes``, then close the descriptor.
  ///
  /// Business Justification: closing a socket with unread input makes the
  /// kernel send a reset that can destroy the last reply (ADR-0026).
  ///
  /// Errors: none. Side Effects: closes the socket. Complexity: O(n).
  /// Thread Safety: one thread. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `connection.close()`.
  func close() {
    shutdown(fd, Int32(SHUT_WR))
    setTimeout(milliseconds: lingerMilliseconds)
    var discarded = 0
    while discarded <= lingerBytes {
      let chunk = receive(max: 4096)
      if chunk.isEmpty { break }
      discarded += chunk.count
    }
    Glibc.close(fd)
  }
}

/// The state shared by the accept thread, the connection threads and
/// ``DigitServer/stop()``.
///
/// Thread Safety: guarded by the server's mutex.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
struct ServerState {
  /// Open connections by descriptor, true while a request is served.
  var connections: [Int32: Bool] = [:]
  /// True once the server stops.
  var stopping = false
  /// True while the accept thread runs.
  var accepting = true
}

/// Holds the body of a new thread until it starts.
///
/// Thread Safety: handed from the creating thread to the new one.
/// Owner: AEC. Since: digit-6 0.1.0.
final class ThreadBody {
  /// The code the thread runs.
  let run: () -> Void

  /// Wrap the code of a thread.
  ///
  /// - Parameter run: The code.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `ThreadBody { work() }`.
  init(_ run: @escaping () -> Void) { self.run = run }
}

/// Start a detached thread with a small stack.
///
/// - Parameter body: The code the thread runs.
/// - Returns: True when the thread started.
///
/// Errors: none (false when the system refuses a thread). Side Effects:
/// creates a thread. Complexity: O(1). Thread Safety: safe. Owner: AEC.
/// Since: digit-6 0.1.0.
///
/// Example: `startThread { serve(fd) }`.
func startThread(_ body: @escaping () -> Void) -> Bool {
  var attributes = pthread_attr_t()
  pthread_attr_init(&attributes)
  defer { pthread_attr_destroy(&attributes) }
  pthread_attr_setstacksize(&attributes, threadStackSize)
  pthread_attr_setdetachstate(&attributes, Int32(PTHREAD_CREATE_DETACHED))
  let box = Unmanaged.passRetained(ThreadBody(body)).toOpaque()
  var thread = pthread_t()
  let status = pthread_create(
    &thread, &attributes,
    { argument in
      Unmanaged<ThreadBody>.fromOpaque(argument!).takeRetainedValue().run()
      return nil
    }, box)
  if status != 0 {
    Unmanaged<ThreadBody>.fromOpaque(box).release()
  }
  return status == 0
}

/// Sleep for a number of milliseconds.
///
/// - Parameter milliseconds: Duration.
///
/// Errors: none. Side Effects: blocks the thread. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `sleepMilliseconds(20)`.
func sleepMilliseconds(_ milliseconds: Int) {
  var duration = timespec(tv_sec: milliseconds / 1000, tv_nsec: (milliseconds % 1000) * 1_000_000)
  nanosleep(&duration, nil)
}

/// The HTTP server of the digit service.
///
/// Description: an accept thread starts one thread per connection; the
/// contract is called under a mutex, so the store and the metrics are
/// never used concurrently.
///
/// Business Justification: the transport of the digit contract on port
/// 8080 (CLAUDE.md 6.1).
///
/// Thread Safety: safe; the shared state is guarded by a mutex (hence
/// `@unchecked Sendable` for the contract it holds).
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public final class DigitServer: @unchecked Sendable {
  /// The listening socket.
  private let listener: Int32
  /// The bound port.
  public let port: Int
  /// The contract.
  private let api: Api
  /// Logger.
  private let log: Logger
  /// Connections and flags.
  private let state = Mutex(ServerState())
  /// Serialises calls to the contract.
  private let apiLock = Mutex(())

  /// Bind a port on all IPv4 addresses and start serving.
  ///
  /// Description: the bind happens here, so a port in use fails the
  /// start. Above ``maxConnections`` a new connection is closed at once.
  ///
  /// Business Justification: port 8080 of every service (CLAUDE.md 6.1).
  ///
  /// - Parameters:
  ///   - port: TCP port, 1...65535 (0 picks a free port, for the tests).
  ///   - api: The contract that answers each request.
  ///   - log: Logger.
  /// - Throws: ``ServerError`` when the socket cannot be bound or the
  ///   accept thread cannot start.
  ///
  /// Side Effects: opens a socket; starts the accept thread.
  /// Complexity: O(1). Thread Safety: call once. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `let server = try DigitServer(port: 8080, api: api, log: log)`.
  ///
  /// See Also: ``stop()``.
  public init(port: Int, api: Api, log: Logger) throws {
    let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    guard fd >= 0 else { throw ServerError(message: String(cString: strerror(errno))) }
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port).bigEndian)
    address.sin_addr = in_addr(s_addr: INADDR_ANY)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0, listen(fd, 256) == 0 else {
      let message = String(cString: strerror(errno))
      Glibc.close(fd)
      throw ServerError(message: message)
    }
    var actual = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &actual) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    listener = fd
    self.port = Int(UInt16(bigEndian: actual.sin_port))
    self.api = api
    self.log = log
    guard startThread({ self.acceptLoop() }) else {
      Glibc.close(fd)
      throw ServerError(message: "cannot start the accept thread")
    }
  }

  /// Accept connections until the server stops.
  ///
  /// Description: each accepted connection gets its own thread; above
  /// ``maxConnections`` it is closed at once. A failed accept (for example
  /// too many open files) is logged and retried after 200 ms.
  ///
  /// Errors: none. Side Effects: accepts sockets; starts threads; logs.
  /// Complexity: O(1) per connection. Thread Safety: the accept thread.
  /// Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `startThread { self.acceptLoop() }`.
  private func acceptLoop() {
    while true {
      let fd = accept(listener, nil, nil)
      if state.withLock({ $0.stopping }) {
        if fd >= 0 { Glibc.close(fd) }
        break
      }
      guard fd >= 0 else {
        log.write(.warn, "accept failed", detail: String(cString: strerror(errno)))
        sleepMilliseconds(200)
        continue
      }
      let admitted = state.withLock { state in
        guard state.connections.count < maxConnections else { return false }
        state.connections[fd] = false
        return true
      }
      guard admitted else {
        log.write(.warn, "connection limit reached; connection closed", detail: "\(maxConnections)")
        Glibc.close(fd)
        continue
      }
      if !startThread({ self.serve(fd) }) {
        log.write(.warn, "cannot start a connection thread")
        _ = state.withLock { $0.connections.removeValue(forKey: fd) }
        Glibc.close(fd)
      }
    }
    state.withLock { $0.accepting = false }
  }

  /// Serve one connection on its own thread, then close it.
  ///
  /// - Parameter fd: The accepted socket.
  ///
  /// Errors: none. Side Effects: socket I/O; calls the contract under the
  /// lock; updates the state. Complexity: that of the requests.
  /// Thread Safety: one thread per connection. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `startThread { self.serve(fd) }`.
  private func serve(_ fd: Int32) {
    let connection = SocketConnection(fd: fd)
    let api = api
    serveConnection(
      connection,
      handler: { method, path in
        self.apiLock.withLock { _ in api.handle(method: method, path: path) }
      },
      stopping: { self.state.withLock { $0.stopping } },
      busy: { busy in self.state.withLock { $0.connections[fd] = busy } },
      log: log)
    _ = state.withLock { $0.connections.removeValue(forKey: fd) }
    connection.close()
  }

  /// Stop the server.
  ///
  /// Description: stops accepting, shuts the idle connections down and
  /// waits up to ``drainTimeoutSeconds`` for running requests, which are
  /// answered with Connection: close; then shuts down what is left.
  ///
  /// Business Justification: graceful shutdown in at most 10 s
  /// (CLAUDE.md 6.1).
  ///
  /// Errors: none. Side Effects: closes sockets. Complexity: O(c) in the
  /// open connections. Thread Safety: call once. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `server.stop()`.
  ///
  /// See Also: ``init(port:api:log:)``.
  public func stop() {
    let idle = state.withLock { state in
      state.stopping = true
      return state.connections.filter { !$0.value }.map(\.key)
    }
    shutdown(listener, Int32(SHUT_RDWR))
    for fd in idle {
      shutdown(fd, Int32(SHUT_RD))
    }
    var waited = 0
    while waited < drainTimeoutSeconds * 1000,
      state.withLock({ !$0.connections.isEmpty || $0.accepting })
    {
      sleepMilliseconds(20)
      waited += 20
    }
    for fd in state.withLock({ Array($0.connections.keys) }) {
      shutdown(fd, Int32(SHUT_RDWR))
    }
    Glibc.close(listener)
  }
}

/// A failure to start the server.
///
/// Thread Safety: a value type; safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public struct ServerError: Error, CustomStringConvertible {
  /// The system error message.
  public let message: String

  /// The message, for logs.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `"\(error)"`.
  public var description: String { message }
}
