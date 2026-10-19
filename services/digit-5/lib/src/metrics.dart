// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          lib/src/metrics.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Prometheus metrics of the digit service: the request
//                  counter shared by all ten digit services and the build
//                  information.
// Related Docs:    contracts/http/digit.yaml (GET /metrics), ADR-0021

/// Request counter digit_requests_total and its exposition.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

/// Arithmetic endpoint, label endpoint of the counter.
///
/// Thread Safety: immutable. Owner: AEC. Since: digit-5 0.1.0.
enum Endpoint {
  /// GET /value.
  value,

  /// GET /next.
  next,
}

/// Outcome of a request, label outcome of the counter.
///
/// Thread Safety: immutable. Owner: AEC. Since: digit-5 0.1.0.
enum Outcome {
  /// Answered 200.
  ok,

  /// Answered 503 (database unavailable).
  error,
}

/// Counters of one service process; every sample exists from the start
/// (value 0).
///
/// Business Justification: one dashboard shows the traffic of all ten
/// digit services (P7.3).
///
/// Thread Safety: one isolate; Dart runs the handlers of an isolate one at
/// a time. Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
class Metrics {
  /// Create zeroed counters.
  ///
  /// Parameters:
  /// - [digit]: the service's digit, 0..9.
  /// - [version]: service version.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: not applicable. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `final metrics = Metrics(5, '0.1.0');`
  ///
  /// See Also: [count].
  Metrics(this.digit, this.version);

  /// Value of the digit label, 0..9.
  final int digit;

  /// Service version for digit_build_info.
  final String version;

  /// digit_requests_total samples by endpoint and outcome.
  final Map<(Endpoint, Outcome), int> _requests = {
    for (final endpoint in Endpoint.values)
      for (final outcome in Outcome.values) (endpoint, outcome): 0,
  };

  /// Count one answered request.
  ///
  /// Business Justification: traffic and errors per digit.
  ///
  /// Parameters:
  /// - [endpoint]: endpoint answered.
  /// - [outcome]: outcome of the request.
  ///
  /// Errors: none. Side Effects: increments one counter. Complexity: O(1).
  /// Thread Safety: one isolate. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `metrics.count(Endpoint.next, Outcome.ok);`
  ///
  /// See Also: [render].
  void count(Endpoint endpoint, Outcome outcome) {
    _requests[(endpoint, outcome)] = get(endpoint, outcome) + 1;
  }

  /// Current value of one sample (used by the unit tests).
  ///
  /// Parameters:
  /// - [endpoint]: endpoint.
  /// - [outcome]: outcome.
  ///
  /// Returns: the number of counted requests.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// one isolate. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `metrics.get(Endpoint.next, Outcome.error)`.
  ///
  /// See Also: [count].
  int get(Endpoint endpoint, Outcome outcome) =>
      _requests[(endpoint, outcome)]!;

  /// Render the Prometheus text exposition (format 0.0.4).
  ///
  /// Description: digit_requests_total with labels digit, endpoint and
  /// outcome (all four samples) and digit_build_info with labels digit and
  /// version, value 1.
  ///
  /// Business Justification: GET /metrics of the contract.
  ///
  /// Returns: the exposition text.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// one isolate. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `final text = metrics.render();`
  ///
  /// See Also: [count].
  String render() {
    final text = StringBuffer()
      ..writeln(
        '# HELP digit_requests_total Requests answered by the digit service.',
      )
      ..writeln('# TYPE digit_requests_total counter');
    for (final endpoint in Endpoint.values) {
      for (final outcome in Outcome.values) {
        text.writeln(
          'digit_requests_total{digit="$digit",endpoint="${endpoint.name}",'
          'outcome="${outcome.name}"} ${get(endpoint, outcome)}',
        );
      }
    }
    text
      ..writeln(
        '# HELP digit_build_info Build information of the digit service.',
      )
      ..writeln('# TYPE digit_build_info gauge')
      ..writeln('digit_build_info{digit="$digit",version="$version"} 1');
    return text.toString();
  }
}
