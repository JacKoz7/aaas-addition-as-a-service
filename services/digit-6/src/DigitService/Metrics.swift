// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          src/DigitService/Metrics.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Prometheus metrics of the digit service: the request
//                  counter shared by all ten digit services and the build
//                  information.
// Related Docs:    contracts/http/digit.yaml (GET /metrics), ADR-0021

/// Arithmetic endpoint, label `endpoint` of the counter.
///
/// Thread Safety: a value type; safe. Owner: AEC. Since: digit-6 0.1.0.
public enum Endpoint: String, CaseIterable, Sendable {
  /// GET /value.
  case value
  /// GET /next.
  case next
}

/// Outcome of a request, label `outcome` of the counter.
///
/// Thread Safety: a value type; safe. Owner: AEC. Since: digit-6 0.1.0.
public enum Outcome: String, CaseIterable, Sendable {
  /// Answered 200.
  case ok
  /// Answered 503 (database unavailable).
  case error
}

/// Counters of one service process; every sample exists from the start
/// (value 0).
///
/// Business Justification: one dashboard shows the traffic of all ten
/// digit services (P7.3).
///
/// Thread Safety: not synchronised; used only through ``Api``, which the
/// server calls under one lock (hence `@unchecked Sendable`, ADR-0028).
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public final class Metrics: @unchecked Sendable {
  /// Value of the digit label, 0...9.
  public let digit: Int
  /// Service version for `digit_build_info`.
  public let version: String
  /// `digit_requests_total` samples, keyed by endpoint and outcome.
  private var requests: [String: Int] = [:]

  /// Create zeroed counters.
  ///
  /// - Parameters:
  ///   - digit: The service's digit, 0...9.
  ///   - version: Service version.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: not applicable. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `let metrics = Metrics(digit: 6, version: "0.1.0")`.
  ///
  /// See Also: ``count(_:_:)``.
  public init(digit: Int, version: String) {
    self.digit = digit
    self.version = version
  }

  /// The key of one sample.
  ///
  /// - Parameters:
  ///   - endpoint: Endpoint.
  ///   - outcome: Outcome.
  /// - Returns: The dictionary key.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `key(.next, .ok) == "next/ok"`.
  private func key(_ endpoint: Endpoint, _ outcome: Outcome) -> String {
    endpoint.rawValue + "/" + outcome.rawValue
  }

  /// Count one answered request.
  ///
  /// Business Justification: traffic and errors per digit.
  ///
  /// - Parameters:
  ///   - endpoint: Endpoint answered.
  ///   - outcome: Outcome of the request.
  ///
  /// Errors: none. Side Effects: increments one counter. Complexity: O(1).
  /// Thread Safety: under the server's lock. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `metrics.count(.next, .ok)`.
  ///
  /// See Also: ``render()``.
  public func count(_ endpoint: Endpoint, _ outcome: Outcome) {
    requests[key(endpoint, outcome), default: 0] += 1
  }

  /// Current value of one sample (used by the unit tests).
  ///
  /// - Parameters:
  ///   - endpoint: Endpoint.
  ///   - outcome: Outcome.
  /// - Returns: The number of counted requests.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// under the server's lock. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `metrics.get(.next, .error)`.
  ///
  /// See Also: ``count(_:_:)``.
  public func get(_ endpoint: Endpoint, _ outcome: Outcome) -> Int {
    requests[key(endpoint, outcome), default: 0]
  }

  /// Render the Prometheus text exposition (format 0.0.4).
  ///
  /// Description: `digit_requests_total` with labels digit, endpoint and
  /// outcome (all four samples) and `digit_build_info` with labels digit
  /// and version, value 1.
  ///
  /// Business Justification: GET /metrics of the contract.
  ///
  /// - Returns: The exposition text.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// under the server's lock. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `let text = metrics.render()`.
  ///
  /// See Also: ``count(_:_:)``.
  public func render() -> String {
    var text =
      "# HELP digit_requests_total Requests answered by the digit service.\n"
      + "# TYPE digit_requests_total counter\n"
    for endpoint in Endpoint.allCases {
      for outcome in Outcome.allCases {
        text +=
          "digit_requests_total{digit=\"\(digit)\",endpoint=\"\(endpoint.rawValue)\","
          + "outcome=\"\(outcome.rawValue)\"} \(get(endpoint, outcome))\n"
      }
    }
    text +=
      "# HELP digit_build_info Build information of the digit service.\n"
      + "# TYPE digit_build_info gauge\n"
      + "digit_build_info{digit=\"\(digit)\",version=\"\(version)\"} 1\n"
    return text
  }
}
