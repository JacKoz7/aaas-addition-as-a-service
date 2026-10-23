//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/metrics.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Request counters of the digit contract and their
////                  Prometheus text exposition (GET /metrics).
//// Related Docs:    contracts/http/digit.yaml, CLAUDE.md 4.4, ADR-0021
////
//// Metrics of the digit-7 service.
////
//// `digit_requests_total{digit, endpoint, outcome}` is shared by the ten
//// digit services (CLAUDE.md 4.4); `digit_build_info` carries the version.
//// The counters are a value held by the contract process (`digit7/api`),
//// which is the only process that changes them.

import gleam/int

/// A contract endpoint that is counted.
///
/// Thread Safety: an immutable value. Owner: Arithmetic Excellence Center
/// (AEC). Since: digit-7 0.1.0.
pub type Endpoint {
  /// `GET /value`.
  Value
  /// `GET /next`.
  Next
}

/// The outcome of a counted request.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type Outcome {
  /// Answered 200 from the database.
  Answered
  /// Answered 503: the database could not be read.
  Failed
}

/// The counters of one service instance since its start.
///
/// Thread Safety: an immutable value; each change returns a new one.
/// Owner: AEC. Since: digit-7 0.1.0.
pub type Metrics {
  /// The digit and version labels and one counter per endpoint and outcome.
  Metrics(
    digit: Int,
    version: String,
    value_ok: Int,
    value_error: Int,
    next_ok: Int,
    next_error: Int,
  )
}

/// Counters at zero for a digit and version.
///
/// Parameters: `digit` — 0..9; `version` — the service version.
/// Returns: the counters. Errors: none. Side Effects: none.
/// Complexity: O(1). Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `new(7, "0.1.0")`.
pub fn new(digit: Int, version: String) -> Metrics {
  Metrics(
    digit:,
    version:,
    value_ok: 0,
    value_error: 0,
    next_ok: 0,
    next_error: 0,
  )
}

/// Count one request.
///
/// Business Justification: the shared counter lets one dashboard show
/// the traffic and error rate of all ten digit services.
/// Parameters: `metrics` — the counters; `endpoint`, `outcome` — what to
/// count. Returns: the counters with one more request. Errors: none.
/// Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `count(new(7, "0.1.0"), Value, Answered)`.
pub fn count(
  metrics: Metrics,
  endpoint: Endpoint,
  outcome: Outcome,
) -> Metrics {
  case endpoint, outcome {
    Value, Answered -> Metrics(..metrics, value_ok: metrics.value_ok + 1)
    Value, Failed -> Metrics(..metrics, value_error: metrics.value_error + 1)
    Next, Answered -> Metrics(..metrics, next_ok: metrics.next_ok + 1)
    Next, Failed -> Metrics(..metrics, next_error: metrics.next_error + 1)
  }
}

/// Read one counter.
///
/// Parameters: `metrics` — the counters; `endpoint`, `outcome` — which
/// counter. Returns: its value. Errors: none. Side Effects: none.
/// Complexity: O(1). Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `get(new(7, "0.1.0"), Next, Answered) == 0`.
pub fn get(metrics: Metrics, endpoint: Endpoint, outcome: Outcome) -> Int {
  case endpoint, outcome {
    Value, Answered -> metrics.value_ok
    Value, Failed -> metrics.value_error
    Next, Answered -> metrics.next_ok
    Next, Failed -> metrics.next_error
  }
}

/// The label value of an endpoint.
///
/// Parameters: `endpoint` — the endpoint. Returns: `value` or `next`.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `endpoint_label(Next) == "next"`.
pub fn endpoint_label(endpoint: Endpoint) -> String {
  case endpoint {
    Value -> "value"
    Next -> "next"
  }
}

/// The label value of an outcome.
///
/// Parameters: `outcome` — the outcome. Returns: `ok` or `error`.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `outcome_label(Failed) == "error"`.
pub fn outcome_label(outcome: Outcome) -> String {
  case outcome {
    Answered -> "ok"
    Failed -> "error"
  }
}

/// One sample line of `digit_requests_total`.
///
/// Parameters: `metrics` — the counters; `endpoint`, `outcome` — the
/// labels. Returns: the line with its newline. Errors: none.
/// Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `sample(m, Value, Answered)`.
fn sample(metrics: Metrics, endpoint: Endpoint, outcome: Outcome) -> String {
  "digit_requests_total{digit=\""
  <> int.to_string(metrics.digit)
  <> "\",endpoint=\""
  <> endpoint_label(endpoint)
  <> "\",outcome=\""
  <> outcome_label(outcome)
  <> "\"} "
  <> int.to_string(get(metrics, endpoint, outcome))
  <> "\n"
}

/// The Prometheus text exposition (format 0.0.4) of the counters.
///
/// Description: four `digit_requests_total` samples (every endpoint and
/// outcome, zeros included) and `digit_build_info`, each with HELP and
/// TYPE lines.
/// Parameters: `metrics` — the counters. Returns: the exposition text.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `render(new(7, "0.1.0"))`.
/// See Also: contracts/http/digit.yaml (`/metrics`).
pub fn render(metrics: Metrics) -> String {
  "# HELP digit_requests_total Requests answered by the digit service.\n"
  <> "# TYPE digit_requests_total counter\n"
  <> sample(metrics, Value, Answered)
  <> sample(metrics, Value, Failed)
  <> sample(metrics, Next, Answered)
  <> sample(metrics, Next, Failed)
  <> "# HELP digit_build_info Build information of the digit service.\n"
  <> "# TYPE digit_build_info gauge\n"
  <> "digit_build_info{digit=\""
  <> int.to_string(metrics.digit)
  <> "\",version=\""
  <> metrics.version
  <> "\"} 1\n"
}
