// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          lib/src/api.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         The HTTP contract of the digit service as a function
//                  from (method, path) to a reply: routing, JSON bodies,
//                  problem details, health and metrics.
// Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022

/// Request handling of contracts/http/digit.yaml, independent of the HTTP
/// server.
///
/// The server passes each request to [Api.handle] and sends the [Reply] it
/// returns; the unit tests call [Api.handle] directly.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

import 'log.dart';
import 'metrics.dart';
import 'store.dart';

/// Media type of JSON bodies.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const String jsonType = 'application/json';

/// Media type of problem details (RFC 9457).
///
/// Owner: AEC. Since: digit-5 0.1.0.
const String problemType = 'application/problem+json';

/// Media type of the Prometheus text exposition.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const String prometheusType = 'text/plain; version=0.0.4';

/// Paths of the contract.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const Set<String> _paths = {'/value', '/next', '/health', '/metrics'};

/// An HTTP reply to send.
///
/// Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
class Reply {
  /// Create a reply.
  ///
  /// Parameters:
  /// - [status]: HTTP status code.
  /// - [contentType]: value of Content-Type.
  /// - [body]: response body.
  /// - [allow]: value of Allow; null when not sent (405 only).
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `const Reply(200, jsonType, '{}')`.
  ///
  /// See Also: [problem].
  const Reply(this.status, this.contentType, this.body, {this.allow});

  /// HTTP status code.
  final int status;

  /// Value of Content-Type.
  final String contentType;

  /// Response body.
  final String body;

  /// Value of Allow; null when not sent.
  final String? allow;
}

/// Build a problem details reply (RFC 9457).
///
/// Description: type is about:blank; title and detail are JSON-escaped.
///
/// Business Justification: every AaaS error is problem details
/// (CLAUDE.md 4.1).
///
/// Parameters:
/// - [status]: HTTP status.
/// - [title]: short summary of the problem type.
/// - [detail]: explanation of this occurrence.
/// - [allow]: value of Allow, for 405.
///
/// Returns: the reply with Content-Type application/problem+json.
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
///
/// Example: `problem(404, 'Not Found', 'no such path')`.
///
/// See Also: [Api.handle].
Reply problem(int status, String title, String detail, {String? allow}) =>
    Reply(
      status,
      problemType,
      '{"type":"about:blank","title":"${jsonEscape(title)}",'
      '"status":$status,"detail":"${jsonEscape(detail)}"}',
      allow: allow,
    );

/// The digit contract over one database.
///
/// Description: holds references to the store and the metrics, which must
/// outlive it.
///
/// Business Justification: the single implementation of the contract that
/// every digit request goes through; the value is read on every request,
/// never cached or hard-coded (CLAUDE.md 4.4).
///
/// Thread Safety: one isolate; [handle] is synchronous.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
class Api {
  /// Bind the contract to a database and counters; nothing is read until
  /// the first request.
  ///
  /// Parameters:
  /// - [_store]: open, migrated database of the service.
  /// - [_digit]: the digit the service represents, 0..9.
  /// - [_metrics]: counters updated by /value and /next.
  /// - [_log]: logger for database failures.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: not applicable. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `final api = Api(store, 5, metrics, log);`
  ///
  /// See Also: [handle].
  Api(this._store, this._digit, this._metrics, this._log);

  /// Database of the service.
  final Store _store;

  /// The configured digit (AAAS_DIGIT).
  final int _digit;

  /// Request counters.
  final Metrics _metrics;

  /// Logger for database failures.
  final Logger _log;

  /// Read the digit row and check that it names the configured digit.
  ///
  /// Description: a failure is logged at error level.
  ///
  /// Business Justification: a service must never answer for another
  /// digit, for example after its volume was mixed up with another one.
  ///
  /// Returns: the row, or null on failure.
  ///
  /// Errors: none (null on failure). Side Effects: one SELECT; logs
  /// failures. Complexity: O(1). Thread Safety: one isolate. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `final row = _readRow();`
  ///
  /// See Also: [Store.read].
  DigitRow? _readRow() {
    final DigitRow row;
    try {
      row = _store.read();
    } on StoreException catch (e) {
      _log.write(
        Level.error,
        'cannot read the digit from the database',
        detail: e.message,
      );
      return null;
    }
    if (row.digit != _digit) {
      _log.write(Level.error, 'the database holds another digit');
      return null;
    }
    return row;
  }

  /// Answer GET /value or GET /next.
  ///
  /// Description: reads the row on every call; 503 problem details when it
  /// cannot be read. Counts the request in the metrics.
  ///
  /// Business Justification: the arithmetic of the digit (CLAUDE.md 4.4).
  ///
  /// Parameters:
  /// - [endpoint]: which of the two operations.
  ///
  /// Returns: the reply.
  ///
  /// Errors: none (503 reply on failure). Side Effects: one SELECT; one
  /// counter increment. Complexity: O(1). Thread Safety: one isolate.
  /// Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `_answerDigit(Endpoint.next)`.
  ///
  /// See Also: [handle].
  Reply _answerDigit(Endpoint endpoint) {
    final row = _readRow();
    if (row == null) {
      _metrics.count(endpoint, Outcome.error);
      return problem(
        503,
        'Service Unavailable',
        'the digit cannot be read from the database; retry the call',
      );
    }
    _metrics.count(endpoint, Outcome.ok);
    return switch (endpoint) {
      Endpoint.value => Reply(
        200,
        jsonType,
        '{"digit":${row.digit},"value":${row.value}}',
      ),
      Endpoint.next => Reply(
        200,
        jsonType,
        '{"digit":${row.digit},"next":${row.next},"carry":${row.carry}}',
      ),
    };
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
  /// Parameters:
  /// - [method]: HTTP method, as received.
  /// - [path]: request path without the query string.
  ///
  /// Returns: the reply.
  ///
  /// Errors: none (404, 405 or 503 replies). Side Effects: reads the
  /// database; updates the metrics; logs database failures.
  /// Complexity: O(1). Thread Safety: one isolate. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `api.handle('GET', '/next')`.
  ///
  /// See Also: [problem].
  Reply handle(String method, String path) {
    if (!_paths.contains(path)) {
      return problem(404, 'Not Found', 'the digit service has no such path');
    }
    if (method != 'GET') {
      return problem(
        405,
        'Method Not Allowed',
        'only GET is allowed on this path',
        allow: 'GET',
      );
    }
    switch (path) {
      case '/value':
        return _answerDigit(Endpoint.value);
      case '/next':
        return _answerDigit(Endpoint.next);
      case '/health':
        return _readRow() != null
            ? const Reply(
                200,
                jsonType,
                '{"status":"ok","checks":{"database":"ok"}}',
              )
            : const Reply(
                503,
                jsonType,
                '{"status":"error","checks":{"database":"error"}}',
              );
      default:
        return Reply(200, prometheusType, _metrics.render());
    }
  }
}
