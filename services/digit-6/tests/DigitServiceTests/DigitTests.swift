// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          tests/DigitServiceTests/DigitTests.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Unit tests of the digit-6 service (swift-testing) against
//                  the real migrations: storage, contract, metrics, trace
//                  context, logging and the HTTP transport.
// Related Docs:    services/digit-6/README.md, contracts/http/digit.yaml,
//                  ADR-0022, ADR-0028

import Synchronization
import Testing

@testable import DigitService

#if canImport(Glibc)
  import Glibc
#elseif canImport(Darwin)
  import Darwin
#endif

/// Directory of the real migrations, relative to the service directory
/// (`swift test` runs there).
///
/// Owner: AEC. Since: digit-6 0.1.0.
let migrations = "migrations"

/// Logger of the tests: lines are dropped, so the output stays readable.
///
/// Owner: AEC. Since: digit-6 0.1.0.
let quiet = Logger(service: "digit-6", threshold: .debug, sink: { _ in })

/// Open an in-memory database migrated with the real migrations.
///
/// Business Justification: every test starts from the shipped schema and
/// seed.
///
/// - Returns: The migrated store.
/// - Throws: ``StoreError`` when the migration fails.
///
/// Side Effects: none outside the in-memory database. Complexity: O(1).
/// Thread Safety: one test at a time per store. Owner: AEC.
/// Since: digit-6 0.1.0.
///
/// Example: `let store = try migrated()`.
func migrated() throws -> Store {
  let store = try Store(path: ":memory:", log: quiet)
  #expect(try store.migrate(migrations) == 1)
  return store
}

/// A contract over a fresh migrated database, with its store and metrics.
///
/// - Returns: The contract, its store and its metrics.
/// - Throws: As ``migrated()``.
///
/// Errors: as ``migrated()``. Side Effects: none. Complexity: O(1).
/// Thread Safety: one test at a time. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `let (api, store, metrics) = try contract()`.
func contract() throws -> (Api, Store, Metrics) {
  let store = try migrated()
  let metrics = Metrics(digit: 6, version: "0.1.0")
  return (Api(store: store, digit: 6, metrics: metrics, log: quiet), store, metrics)
}

/// A connection double with scripted input.
///
/// Description: `receive` returns the next chunk of the input (the whole
/// input in one chunk by default), then nothing; `send` collects the
/// bytes in `output`.
///
/// Thread Safety: one test at a time. Owner: AEC. Since: digit-6 0.1.0.
final class ScriptedConnection: Connection {
  /// Chunks still to deliver.
  private var chunks: [[UInt8]]
  /// Bytes the service sent.
  var output: [UInt8] = []

  /// Create a double that delivers `chunks` in order.
  ///
  /// - Parameter chunks: The client's packets.
  init(_ chunks: [String]) { self.chunks = chunks.map { Array($0.utf8) } }

  /// Deliver the next chunk, at most `max` bytes of it.
  ///
  /// - Parameter max: Most bytes to return.
  /// - Returns: The bytes; empty when the input is exhausted.
  func receive(max: Int) -> [UInt8] {
    guard !chunks.isEmpty else { return [] }
    let chunk = chunks.removeFirst()
    if chunk.count > max {
      chunks.insert(Array(chunk[max...]), at: 0)
      return Array(chunk[..<max])
    }
    return chunk
  }

  /// Collect sent bytes.
  ///
  /// - Parameter bytes: The bytes.
  /// - Returns: True.
  func send(_ bytes: [UInt8]) -> Bool {
    output += bytes
    return true
  }
}

/// Serve scripted input through ``serveConnection(_:handler:stopping:busy:log:)``
/// and return what was sent.
///
/// - Parameter chunks: The client's packets.
/// - Returns: Bytes the service sent, as text.
/// - Throws: As ``contract()``.
///
/// Side Effects: none. Complexity: O(n). Thread Safety: one test at a
/// time. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `let out = try serve("GET /next HTTP/1.1\r\n\r\n")`.
func serve(_ chunks: String...) throws -> String {
  let (api, _, _) = try contract()
  let connection = ScriptedConnection(chunks)
  serveConnection(
    connection, handler: { api.handle(method: $0, path: $1) }, stopping: { false }, busy: { _ in },
    log: quiet)
  return String(decoding: connection.output, as: UTF8.self)
}

/// The status codes of the responses in `out`, in order.
///
/// - Parameter out: Bytes the service sent.
/// - Returns: The status codes.
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
/// Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `statuses(out) == [200, 200]`.
func statuses(_ out: String) -> [Int] {
  // A pipelined response starts right after the previous body, not on a
  // new line, so every occurrence of the status line prefix counts.
  out.split(separator: "HTTP/1.1 ", omittingEmptySubsequences: true).compactMap {
    Int($0.prefix(3))
  }
}

/// Tests of the SQLite store.
///
/// Owner: AEC. Since: digit-6 0.1.0.
@Suite struct StoreTests {
  /// The migrations are applied once.
  ///
  /// - Throws: Store errors.
  @Test func appliesTheMigrationsOnce() throws {
    let store = try migrated()
    #expect(try store.migrate(migrations) == 0)
    #expect(store.isApplied("0001_digit.sql"))
  }

  /// The seeded row is digit 6, value 6, successor 7, no carry.
  ///
  /// - Throws: Store errors.
  @Test func readsTheSeededRow() throws {
    #expect(try migrated().read() == DigitRow(digit: 6, value: 6, next: 7, carry: false))
  }

  /// A missing migrations directory is an error.
  ///
  /// - Throws: Store errors.
  @Test func failsForAMissingDirectory() throws {
    let store = try Store(path: ":memory:", log: quiet)
    #expect(throws: StoreError.self) { try store.migrate("/nonexistent") }
  }

  /// A failing migration is rolled back and not recorded.
  ///
  /// - Throws: Store errors.
  @Test func rollsBackAFailingMigration() throws {
    var template = Array("/tmp/digit6XXXXXX".utf8CString)
    let dir = String(cString: mkdtemp(&template)!)
    let path = dir + "/0001_bad.sql"
    let file = fopen(path, "w")!
    fputs("CREATE TABLE t (x INTEGER); INSERT INTO nope VALUES (1);", file)
    fclose(file)
    let store = try Store(path: ":memory:", log: quiet)
    #expect(throws: StoreError.self) { try store.migrate(dir) }
    unlink(path)
    rmdir(dir)
    #expect(!store.isApplied("0001_bad.sql"))
    #expect(throws: StoreError.self) { try store.execute("SELECT x FROM t;") }
  }

  /// A table with two rows is rejected.
  ///
  /// - Throws: Store errors.
  @Test func rejectsTwoRows() throws {
    let store = try migrated()
    try store.execute("INSERT INTO digit VALUES (7, 7, 8, 0);")
    #expect(throws: StoreError(message: "the table digit holds more than one row")) {
      try store.read()
    }
  }
}

/// Tests of the contract.
///
/// Owner: AEC. Since: digit-6 0.1.0.
@Suite struct ContractTests {
  /// GET /value and GET /next answer from the seed.
  ///
  /// - Throws: Store errors.
  @Test func answersValueAndNext() throws {
    let (api, _, _) = try contract()
    #expect(
      api.handle(method: "GET", path: "/value")
        == Reply(status: 200, contentType: jsonType, body: "{\"digit\":6,\"value\":6}"))
    #expect(
      api.handle(method: "GET", path: "/next").body == "{\"digit\":6,\"next\":7,\"carry\":false}")
  }

  /// The answers come from the database, not from constants.
  ///
  /// - Throws: Store errors.
  @Test func answersFromTheDatabase() throws {
    let (api, store, _) = try contract()
    try store.execute("UPDATE digit SET next = 7, carry = 1;")
    #expect(
      api.handle(method: "GET", path: "/next").body == "{\"digit\":6,\"next\":7,\"carry\":true}")
  }

  /// GET /health reports the database.
  ///
  /// - Throws: Store errors.
  @Test func reportsHealth() throws {
    let (api, store, _) = try contract()
    #expect(
      api.handle(method: "GET", path: "/health").body
        == "{\"status\":\"ok\",\"checks\":{\"database\":\"ok\"}}")
    try store.execute("DROP TABLE digit;")
    #expect(api.handle(method: "GET", path: "/health").status == 503)
  }

  /// A missing row answers 503 and counts an error.
  ///
  /// - Throws: Store errors.
  @Test func answers503AndCountsAnError() throws {
    let (api, store, metrics) = try contract()
    try store.execute("DROP TABLE digit;")
    let reply = api.handle(method: "GET", path: "/next")
    #expect(reply.status == 503)
    #expect(reply.contentType == problemType)
    #expect(metrics.get(.next, .error) == 1)
  }

  /// Another digit in the database answers 503.
  ///
  /// - Throws: Store errors.
  @Test func refusesAnotherDigit() throws {
    let api = Api(
      store: try migrated(), digit: 5, metrics: Metrics(digit: 5, version: "0.1.0"), log: quiet)
    #expect(api.handle(method: "GET", path: "/value").status == 503)
  }

  /// Unknown paths answer 404 and other methods 405 with Allow.
  ///
  /// - Throws: Store errors.
  @Test func answers404And405() throws {
    let (api, _, _) = try contract()
    #expect(
      api.handle(method: "GET", path: "/nope").body
        == "{\"type\":\"about:blank\",\"title\":\"Not Found\",\"status\":404,"
        + "\"detail\":\"the digit service has no such path\"}")
    let wrong = api.handle(method: "POST", path: "/next")
    #expect(wrong.status == 405)
    #expect(wrong.allow == "GET")
  }

  /// The counters are exposed as Prometheus text.
  ///
  /// - Throws: Store errors.
  @Test func exposesTheCounters() throws {
    let (api, _, _) = try contract()
    _ = api.handle(method: "GET", path: "/next")
    let text = api.handle(method: "GET", path: "/metrics").body
    #expect(text.contains("digit_requests_total{digit=\"6\",endpoint=\"next\",outcome=\"ok\"} 1\n"))
    #expect(
      text.contains("digit_requests_total{digit=\"6\",endpoint=\"value\",outcome=\"error\"} 0\n"))
    #expect(text.contains("digit_build_info{digit=\"6\",version=\"0.1.0\"} 1\n"))
  }
}

/// Tests of the trace context and the logging helpers.
///
/// Owner: AEC. Since: digit-6 0.1.0.
@Suite struct TraceAndLogTests {
  /// A valid traceparent is accepted.
  @Test func acceptsAValidTraceparent() {
    #expect(
      TraceContext.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
        == TraceContext(traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7"))
  }

  /// Invalid traceparents are rejected.
  ///
  /// - Parameter header: An invalid header value.
  @Test(arguments: [
    "", "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    "00-00000000000000000000000000000000-00f067aa0ba902b7-01",
    "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",
    "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01",
    "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-x",
  ])
  func rejectsInvalidTraceparents(header: String) {
    #expect(TraceContext.parse(header) == nil)
  }

  /// JSON escaping, level parsing and the log line fields.
  @Test func escapesAndWritesLines() {
    #expect(jsonEscape("a\"b\\c\n\u{1}") == "a\\\"b\\\\c\\n\\u0001")
    #expect(Level.parse("debug", fallback: .info) == .debug)
    #expect(Level.parse("loud", fallback: .info) == .info)
    let lines = LineBox()
    let log = Logger(service: "digit-6", threshold: .info, sink: { lines.append($0) })
    log.write(.debug, "hidden")
    log.write(.warn, "shown", traceId: "abc", detail: "x")
    #expect(lines.all.count == 1)
    let line = lines.all.first ?? ""
    #expect(line.contains("\"level\":\"warn\",\"service\":\"digit-6\",\"msg\":\"shown\""))
    #expect(line.contains("\"taskId\":null,\"traceId\":\"abc\",\"spanId\":null,\"detail\":\"x\"}"))
    #expect(timestamp().count == 24 && timestamp().hasSuffix("Z"))
  }
}

/// Collects log lines in the tests.
///
/// Thread Safety: guarded by a mutex (hence `@unchecked Sendable`).
/// Owner: AEC. Since: digit-6 0.1.0.
final class LineBox: @unchecked Sendable {
  /// The lines, guarded by a mutex.
  private let lock = Mutex<[String]>([])

  /// Add a line.
  ///
  /// - Parameter line: The line.
  func append(_ line: String) { lock.withLock { $0.append(line) } }

  /// Every line so far.
  var all: [String] { lock.withLock { $0 } }
}

/// Tests of the HTTP transport.
///
/// Owner: AEC. Since: digit-6 0.1.0.
@Suite struct TransportTests {
  /// Request lines and header fields are parsed.
  @Test func parsesRequestLinesAndHeaders() {
    let line = parseRequestLine("GET /next?x=1 HTTP/1.1")
    #expect(line?.method == "GET" && line?.target == "/next?x=1" && line?.minor == "1")
    #expect(parseRequestLine("GET /next HTTP/2.0") == nil)
    #expect(parseRequestLine("garbage") == nil)
    #expect(parseHeader("Content-Length:  5 ")! == ("content-length", "5"))
    #expect(parseHeader(" folded") == nil)
  }

  /// HTTP/1.1 connections stay open unless asked to close.
  @Test func keepsConnections() {
    #expect(keepAlive("1", [:]))
    #expect(!keepAlive("1", ["connection": "Close"]))
    #expect(!keepAlive("0", [:]))
    #expect(keepAlive("0", ["connection": "keep-alive"]))
  }

  /// Pipelined requests, also split across packets, are answered in order.
  ///
  /// - Throws: Store errors.
  @Test func servesPipelinedRequests() throws {
    let out = try serve("GET /value HTTP/1.1\r\nHo", "st: x\r\n\r\nGET /next?x=1 HTTP/1.1\r\n\r\n")
    #expect(statuses(out) == [200, 200])
    #expect(out.contains("{\"digit\":6,\"value\":6}"))
    #expect(out.contains("{\"digit\":6,\"next\":7,\"carry\":false}"))
    #expect(!out.contains("Connection: close"))
  }

  /// Bodies are skipped before the next request; 405 carries Allow.
  ///
  /// - Throws: Store errors.
  @Test func skipsBodies() throws {
    let out = try serve(
      "POST /value HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"
        + "GET /next HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n"
        + "GET /value HTTP/1.1\r\n\r\n")
    #expect(statuses(out) == [405, 200, 200])
    #expect(out.contains("Allow: GET\r\n"))
  }

  /// HEAD gets no body; HTTP/1.0 closes.
  ///
  /// - Throws: Store errors.
  @Test func answersHeadAndHttp10() throws {
    let out = try serve("HEAD /next HTTP/1.0\r\n\r\nGET /value HTTP/1.1\r\n\r\n")
    #expect(statuses(out) == [405])
    #expect(out.hasSuffix("Connection: close\r\n\r\n"))
  }

  /// Malformed and oversized requests are rejected and end the connection.
  ///
  /// - Throws: Store errors.
  @Test func rejectsMalformedRequests() throws {
    #expect(statuses(try serve("garbage\r\n\r\nGET /value HTTP/1.1\r\n\r\n")) == [400])
    #expect(statuses(try serve("GET /value HTTP/1.1\r\nbad header\r\n\r\n")) == [400])
    #expect(statuses(try serve("GET /value HTTP/1.1\r\nContent-Length: x\r\n\r\n")) == [400])
    #expect(
      statuses(
        try serve("POST /value HTTP/1.1\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n")
      )
        == [400])
    #expect(
      statuses(try serve("POST /value HTTP/1.1\r\nContent-Length: \(maxBody + 1)\r\n\r\n")) == [413]
    )
    let out = try serve(
      "GET /value HTTP/1.1\r\nX: " + String(repeating: "a", count: maxHead) + "\r\n\r\n")
    #expect(statuses(out) == [431])
    #expect(out.contains(problemType))
  }

  /// A client that closes between requests gets nothing.
  ///
  /// - Throws: Store errors.
  @Test func endsQuietly() throws {
    #expect(try serve("") == "")
    #expect(try serve("\r\n") == "")
  }

  /// The server serves over TCP and stops.
  ///
  /// - Throws: Bind and store errors.
  @Test func servesOverTcpAndStops() throws {
    let (api, _, _) = try contract()
    let server = try DigitServer(port: 0, api: api, log: quiet)
    #expect(server.port > 0)
    let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(server.port).bigEndian)
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    #expect(connected == 0)
    let request = Array("GET /next HTTP/1.1\r\nConnection: close\r\n\r\n".utf8)
    _ = request.withUnsafeBytes { Glibc.send(fd, $0.baseAddress, $0.count, 0) }
    var received: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 1024)
    while true {
      let count = recv(fd, &chunk, chunk.count, 0)
      if count <= 0 { break }
      received += chunk[0..<count]
    }
    close(fd)
    let out = String(decoding: received, as: UTF8.self)
    #expect(statuses(out) == [200])
    #expect(out.hasSuffix("{\"digit\":6,\"next\":7,\"carry\":false}"))
    server.stop()
  }
}
