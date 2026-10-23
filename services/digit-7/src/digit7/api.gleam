//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/api.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         The HTTP contract of the digit service as a function
////                  from (method, path) to a reply, run by one contract
////                  process that owns the database and the counters.
//// Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022, ADR-0029
////
//// The digit contract (CLAUDE.md 4.4): `GET /value`, `GET /next`,
//// `GET /health` and `GET /metrics`, with problem details (RFC 9457) for
//// 404, 405 and 503.
////
//// `handle` is a pure function of the state. `start` runs it in one OTP
//// actor, the contract process: connection processes call it with
//// `answer`, so the SQLite connection and the counters are only ever used
//// by that process.

import digit7/log.{type Logger}
import digit7/metrics.{type Endpoint, type Metrics}
import digit7/store.{type DigitRow, type Store}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

/// Media type of JSON bodies.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
pub const json_type = "application/json"

/// Media type of problem details (RFC 9457).
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub const problem_type = "application/problem+json"

/// Media type of the Prometheus text exposition.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub const prometheus_type = "text/plain; version=0.0.4"

/// Milliseconds a connection process waits for the contract process.
///
/// Description: SQLite waits at most 2 s for a lock (`digit7/store`); a
/// reply later than this is answered 503 instead.
/// Owner: AEC. Since: digit-7 0.1.0.
pub const answer_timeout_ms = 5000

/// An HTTP reply to send.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type Reply {
  /// Status code, Content-Type, body and the Allow value (405 only).
  Reply(status: Int, content_type: String, body: String, allow: Option(String))
}

/// The state of the contract process.
///
/// Thread Safety: owned by the contract process. Owner: AEC.
/// Since: digit-7 0.1.0.
pub type State {
  /// The database, the configured digit, the counters and the logger.
  State(store: Store, digit: Int, metrics: Metrics, log: Logger)
}

/// A message to the contract process.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type Message {
  /// Answer a request and send the reply to `reply_to`.
  Handle(method: String, path: String, reply_to: Subject(Reply))
}

/// Build a problem details reply (RFC 9457).
///
/// Description: `type` is `about:blank`; title and detail are
/// JSON-escaped.
/// Business Justification: every AaaS error is problem details
/// (CLAUDE.md 4.1).
/// Parameters: `status` — HTTP status; `title` — short summary of the
/// problem type; `detail` — explanation of this occurrence; `allow` — the
/// Allow value, if any. Returns: the reply. Errors: none.
/// Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `problem(404, "Not Found", "no such path", None)`.
pub fn problem(
  status: Int,
  title: String,
  detail: String,
  allow: Option(String),
) -> Reply {
  Reply(
    status:,
    content_type: problem_type,
    body: "{\"type\":\"about:blank\",\"title\":\""
      <> log.json_escape(title)
      <> "\",\"status\":"
      <> int.to_string(status)
      <> ",\"detail\":\""
      <> log.json_escape(detail)
      <> "\"}",
    allow:,
  )
}

/// Whether a path belongs to the contract.
///
/// Parameters: `path` — the request path without its query. Returns: True
/// for `/value`, `/next`, `/health` and `/metrics`. Errors: none.
/// Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `is_contract_path("/next") == True`.
fn is_contract_path(path: String) -> Bool {
  case path {
    "/value" | "/next" | "/health" | "/metrics" -> True
    _ -> False
  }
}

/// Read the digit row and check that it holds the configured digit.
///
/// Parameters: `state` — the contract state. Returns: the row.
/// Errors: `Nil` when the database cannot be read or holds another
/// digit; the reason is logged at error level.
/// Side Effects: reads the database; may log. Complexity: O(1).
/// Thread Safety: contract process only. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `read_row(state) == Ok(DigitRow(7, 7, 8, False))`.
fn read_row(state: State) -> Result(DigitRow, Nil) {
  case store.read(state.store) {
    Error(store.StoreError(message)) -> {
      log.event(
        state.log,
        log.Error,
        "cannot read the digit from the database",
        Some(message),
      )
      Error(Nil)
    }
    Ok(row) if row.digit != state.digit -> {
      log.event(state.log, log.Error, "the database holds another digit", None)
      Error(Nil)
    }
    Ok(row) -> Ok(row)
  }
}

/// Answer `GET /value` or `GET /next` from the database.
///
/// Description: 200 with `{digit, value}` or `{digit, next, carry}`; 503
/// problem details when the row cannot be read. Counts the request.
/// Business Justification: the digit services are the authoritative
/// source of each digit for the successor service (CLAUDE.md 3, step 7).
/// Parameters: `state` — the contract state; `endpoint` — which endpoint.
/// Returns: the state with the request counted, and the reply.
/// Errors: none (503 is a reply). Side Effects: reads the database.
/// Complexity: O(1). Thread Safety: contract process only. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `answer_digit(state, metrics.Next)`.
fn answer_digit(state: State, endpoint: Endpoint) -> #(State, Reply) {
  case read_row(state) {
    Error(Nil) -> #(
      State(
        ..state,
        metrics: metrics.count(state.metrics, endpoint, metrics.Failed),
      ),
      problem(
        503,
        "Service Unavailable",
        "the digit cannot be read from the database; retry the call",
        None,
      ),
    )
    Ok(row) -> {
      let body = case endpoint {
        metrics.Value ->
          "{\"digit\":"
          <> int.to_string(row.digit)
          <> ",\"value\":"
          <> int.to_string(row.value)
          <> "}"
        metrics.Next ->
          "{\"digit\":"
          <> int.to_string(row.digit)
          <> ",\"next\":"
          <> int.to_string(row.next)
          <> ",\"carry\":"
          <> case row.carry {
            True -> "true"
            False -> "false"
          }
          <> "}"
      }
      #(
        State(
          ..state,
          metrics: metrics.count(state.metrics, endpoint, metrics.Answered),
        ),
        Reply(200, json_type, body, None),
      )
    }
  }
}

/// Answer one request of the contract.
///
/// Description: unknown paths are 404 for every method; other methods
/// than GET on a contract path are 405 with `Allow: GET`; `/health` is
/// 200 `{status: ok}` when the digit row can be read and 503
/// `{status: error}` otherwise; `/metrics` is the Prometheus exposition.
/// Business Justification: one function holds the whole contract, so the
/// unit tests check it without a socket.
/// Parameters: `state` — the contract state; `method` — the request
/// method; `path` — the request path without its query.
/// Returns: the new state and the reply. Errors: none.
/// Side Effects: reads the database for `/value`, `/next` and `/health`.
/// Complexity: O(1). Thread Safety: contract process only. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `handle(state, "GET", "/value")`.
/// See Also: contracts/http/digit.yaml.
pub fn handle(state: State, method: String, path: String) -> #(State, Reply) {
  case is_contract_path(path), method, path {
    False, _, _ -> #(
      state,
      problem(404, "Not Found", "the digit service has no such path", None),
    )
    True, "GET", "/value" -> answer_digit(state, metrics.Value)
    True, "GET", "/next" -> answer_digit(state, metrics.Next)
    True, "GET", "/health" ->
      case read_row(state) {
        Ok(_) -> #(
          state,
          Reply(
            200,
            json_type,
            "{\"status\":\"ok\",\"checks\":{\"database\":\"ok\"}}",
            None,
          ),
        )
        Error(Nil) -> #(
          state,
          Reply(
            503,
            json_type,
            "{\"status\":\"error\",\"checks\":{\"database\":\"error\"}}",
            None,
          ),
        )
      }
    True, "GET", _ -> #(
      state,
      Reply(200, prometheus_type, metrics.render(state.metrics), None),
    )
    True, _, _ -> #(
      state,
      problem(
        405,
        "Method Not Allowed",
        "only GET is allowed on this path",
        Some("GET"),
      ),
    )
  }
}

/// Handle one message of the contract process.
///
/// Parameters: `state` — the contract state; `message` — the request.
/// Returns: the next state of the actor. Errors: none.
/// Side Effects: those of `handle`; sends the reply.
/// Complexity: O(1). Thread Safety: contract process only. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `on_message(state, Handle("GET", "/next", reply_to))`.
fn on_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Handle(method, path, reply_to) -> {
      let #(state, reply) = handle(state, method, path)
      process.send(reply_to, reply)
      actor.continue(state)
    }
  }
}

/// Start the contract process.
///
/// Business Justification: one process owns the SQLite connection and
/// the counters, so they are never used concurrently.
/// Parameters: `state` — the initial state (the store is handed over to
/// the new process). Returns: the subject to send requests to.
/// Errors: `actor.StartError` when the process cannot start.
/// Side Effects: spawns a process linked to the caller.
/// Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `start(State(store, 7, metrics.new(7, "0.1.0"), logger))`.
pub fn start(state: State) -> Result(Subject(Message), actor.StartError) {
  actor.new(state)
  |> actor.on_message(on_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

/// Ask the contract process for the reply to a request.
///
/// Description: waits up to `answer_timeout_ms`; a later reply is
/// dropped and the request is answered 503.
/// Parameters: `contract` — the contract process; `method`, `path` — the
/// request. Returns: the reply. Errors: none (a timeout is a 503 reply).
/// Side Effects: a message round trip to the contract process.
/// Complexity: O(1). Thread Safety: safe from any process. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `answer(contract, "GET", "/value")`.
pub fn answer(
  contract: Subject(Message),
  method: String,
  path: String,
) -> Reply {
  let reply_to = process.new_subject()
  process.send(contract, Handle(method, path, reply_to))
  case process.receive(reply_to, answer_timeout_ms) {
    Ok(reply) -> reply
    Error(Nil) ->
      problem(
        503,
        "Service Unavailable",
        "the digit service did not answer in time; retry the call",
        None,
      )
  }
}
