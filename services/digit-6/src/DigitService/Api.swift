// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          src/DigitService/Api.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         The HTTP contract of the digit service as a function
//                  from (method, path) to a reply: routing, JSON bodies,
//                  problem details, health and metrics.
// Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022

/// Media type of JSON bodies.
///
/// Owner: AEC. Since: digit-6 0.1.0.
public let jsonType = "application/json"

/// Media type of problem details (RFC 9457).
///
/// Owner: AEC. Since: digit-6 0.1.0.
public let problemType = "application/problem+json"

/// Media type of the Prometheus text exposition.
///
/// Owner: AEC. Since: digit-6 0.1.0.
public let prometheusType = "text/plain; version=0.0.4"

/// Paths of the contract.
///
/// Owner: AEC. Since: digit-6 0.1.0.
private let paths: Set<String> = ["/value", "/next", "/health", "/metrics"]

/// An HTTP reply to send.
///
/// Thread Safety: a value type; safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public struct Reply: Equatable, Sendable {
  /// HTTP status code.
  public let status: Int
  /// Value of Content-Type.
  public let contentType: String
  /// Response body.
  public let body: String
  /// Value of Allow; nil when not sent (405 only).
  public let allow: String?

  /// Create a reply.
  ///
  /// - Parameters:
  ///   - status: HTTP status code.
  ///   - contentType: Value of Content-Type.
  ///   - body: Response body.
  ///   - allow: Value of Allow, nil when not sent.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `Reply(status: 200, contentType: jsonType, body: "{}")`.
  ///
  /// See Also: ``problem(_:_:_:allow:)``.
  public init(status: Int, contentType: String, body: String, allow: String? = nil) {
    self.status = status
    self.contentType = contentType
    self.body = body
    self.allow = allow
  }
}

/// Build a problem details reply (RFC 9457).
///
/// Description: `type` is `about:blank`; title and detail are
/// JSON-escaped.
///
/// Business Justification: every AaaS error is problem details
/// (CLAUDE.md 4.1).
///
/// - Parameters:
///   - status: HTTP status.
///   - title: Short summary of the problem type.
///   - detail: Explanation of this occurrence.
///   - allow: Value of Allow, for 405.
/// - Returns: The reply with Content-Type `application/problem+json`.
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
///
/// Example: `problem(404, "Not Found", "no such path")`.
///
/// See Also: ``Api/handle(method:path:)``.
public func problem(_ status: Int, _ title: String, _ detail: String, allow: String? = nil)
  -> Reply
{
  Reply(
    status: status, contentType: problemType,
    body: "{\"type\":\"about:blank\",\"title\":\"\(jsonEscape(title))\",\"status\":\(status),"
      + "\"detail\":\"\(jsonEscape(detail))\"}",
    allow: allow)
}

/// The digit contract over one database.
///
/// Description: holds references to the store and the metrics, which must
/// outlive it.
///
/// Business Justification: the single implementation of the contract that
/// every digit request goes through; the value is read on every request,
/// never cached or hard-coded (CLAUDE.md 4.4).
///
/// Thread Safety: not synchronised; the server calls it under one lock,
/// which also covers the store and the metrics it holds (hence
/// `@unchecked Sendable`, ADR-0028).
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public final class Api: @unchecked Sendable {
  /// Database of the service.
  private let store: Store
  /// The configured digit (`AAAS_DIGIT`).
  private let digit: Int
  /// Request counters.
  private let metrics: Metrics
  /// Logger for database failures.
  private let log: Logger

  /// Bind the contract to a database and counters; nothing is read until
  /// the first request.
  ///
  /// - Parameters:
  ///   - store: Open, migrated database of the service.
  ///   - digit: The digit the service represents, 0...9.
  ///   - metrics: Counters updated by /value and /next.
  ///   - log: Logger for database failures.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: not applicable. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `let api = Api(store: store, digit: 6, metrics: metrics, log: log)`.
  ///
  /// See Also: ``handle(method:path:)``.
  public init(store: Store, digit: Int, metrics: Metrics, log: Logger) {
    self.store = store
    self.digit = digit
    self.metrics = metrics
    self.log = log
  }

  /// Read the digit row and check that it names the configured digit.
  ///
  /// Description: a failure is logged at error level.
  ///
  /// Business Justification: a service must never answer for another
  /// digit, for example after its volume was mixed up with another one.
  ///
  /// - Returns: The row, or nil on failure.
  ///
  /// Errors: none (nil). Side Effects: one SELECT; logs failures.
  /// Complexity: O(1). Thread Safety: under the server's lock. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `let row = readRow()`.
  ///
  /// See Also: ``Store/read()``.
  private func readRow() -> DigitRow? {
    let row: DigitRow
    do {
      row = try store.read()
    } catch {
      log.write(.error, "cannot read the digit from the database", detail: "\(error)")
      return nil
    }
    guard row.digit == digit else {
      log.write(.error, "the database holds another digit")
      return nil
    }
    return row
  }

  /// Answer GET /value or GET /next.
  ///
  /// Description: reads the row on every call; 503 problem details when it
  /// cannot be read. Counts the request in the metrics.
  ///
  /// Business Justification: the arithmetic of the digit (CLAUDE.md 4.4).
  ///
  /// - Parameter endpoint: Which of the two operations.
  /// - Returns: The reply.
  ///
  /// Errors: none (503 reply). Side Effects: one SELECT; one counter
  /// increment. Complexity: O(1). Thread Safety: under the server's lock.
  /// Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `answerDigit(.next)`.
  ///
  /// See Also: ``handle(method:path:)``.
  private func answerDigit(_ endpoint: Endpoint) -> Reply {
    guard let row = readRow() else {
      metrics.count(endpoint, .error)
      return problem(
        503, "Service Unavailable", "the digit cannot be read from the database; retry the call")
    }
    metrics.count(endpoint, .ok)
    switch endpoint {
    case .value:
      return Reply(
        status: 200, contentType: jsonType, body: "{\"digit\":\(row.digit),\"value\":\(row.value)}")
    case .next:
      return Reply(
        status: 200, contentType: jsonType,
        body: "{\"digit\":\(row.digit),\"next\":\(row.next),\"carry\":\(row.carry)}")
    }
  }

  /// Answer one request according to contracts/http/digit.yaml.
  ///
  /// Description: GET /value answers 200 with digit and value; GET /next
  /// 200 with digit, next and carry, both from the database; GET /health
  /// 200 with status ok and checks.database ok when the row can be read
  /// and names the configured digit, otherwise 503 with error; GET
  /// /metrics 200 Prometheus text; another method on one of these paths
  /// 405 problem details with Allow: GET; any other path 404 problem
  /// details. When the row cannot be read or names another digit, /value
  /// and /next answer 503 problem details and count an error.
  ///
  /// Business Justification: the arithmetic of the digit (CLAUDE.md 4.4).
  ///
  /// - Parameters:
  ///   - method: HTTP method, as received.
  ///   - path: Request path without the query string.
  /// - Returns: The reply.
  ///
  /// Errors: none (404, 405 or 503 replies). Side Effects: reads the
  /// database; updates the metrics; logs database failures.
  /// Complexity: O(1). Thread Safety: under the server's lock. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `api.handle(method: "GET", path: "/next")`.
  ///
  /// See Also: ``problem(_:_:_:allow:)``.
  public func handle(method: String, path: String) -> Reply {
    guard paths.contains(path) else {
      return problem(404, "Not Found", "the digit service has no such path")
    }
    guard method == "GET" else {
      return problem(405, "Method Not Allowed", "only GET is allowed on this path", allow: "GET")
    }
    switch path {
    case "/value":
      return answerDigit(.value)
    case "/next":
      return answerDigit(.next)
    case "/health":
      return readRow() != nil
        ? Reply(
          status: 200, contentType: jsonType,
          body: "{\"status\":\"ok\",\"checks\":{\"database\":\"ok\"}}")
        : Reply(
          status: 503, contentType: jsonType,
          body: "{\"status\":\"error\",\"checks\":{\"database\":\"error\"}}")
    default:
      return Reply(status: 200, contentType: prometheusType, body: metrics.render())
    }
  }
}
