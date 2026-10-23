//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          test/digit7/support_test.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Unit tests of the supporting modules: logging, trace
////                  context, metrics, the connection tracker and the
////                  SIGTERM handler.
//// Related Docs:    CLAUDE.md 6.1, ADR-0029
////
//// Tests of `digit7/log`, `digit7/trace`, `digit7/metrics`,
//// `digit7/tracker` and `digit7/signal`.

import digit7/log
import digit7/metrics
import digit7/signal
import digit7/trace
import digit7/tracker
import digit7_test
import gleam/erlang/atom
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// Log lines are one JSON object with the fields of CLAUDE.md 6.1.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
pub fn log_line_test() {
  let lines = process.new_subject()
  let logger = digit7_test.capture(lines)
  log.write(
    logger,
    log.Info,
    "request \"answered\"",
    Some("4bf92f3577b34da6a3ce929d0e0e4736"),
    Some("00f067aa0ba902b7"),
    Some("tab\there"),
  )
  let assert Ok(line) = process.receive(lines, 100)
  assert string.starts_with(line, "{\"ts\":\"")
  assert string.contains(
    line,
    "Z\",\"level\":\"info\",\"service\":\"digit-7\","
      <> "\"msg\":\"request \\\"answered\\\"\",\"taskId\":null,"
      <> "\"traceId\":\"4bf92f3577b34da6a3ce929d0e0e4736\","
      <> "\"spanId\":\"00f067aa0ba902b7\",\"detail\":\"tab\\there\"}",
  )
}

/// Lines below the threshold are dropped; levels parse with a fallback.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn log_threshold_test() {
  let lines = process.new_subject()
  let logger = log.Logger(..digit7_test.capture(lines), threshold: log.Warn)
  log.event(logger, log.Info, "dropped", None)
  log.event(logger, log.Error, "kept", None)
  let assert Ok(line) = process.receive(lines, 100)
  assert string.contains(
    line,
    "\"msg\":\"kept\",\"taskId\":null,\"traceId\":null",
  )
  assert process.receive(lines, 0) == Error(Nil)
  assert log.parse_level("debug", log.Info) == log.Debug
  assert log.parse_level("verbose", log.Info) == log.Info
}

/// Timestamps are RFC 3339 UTC with milliseconds.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn timestamp_test() {
  let ts = log.timestamp()
  assert string.length(ts) == 24
  assert string.ends_with(ts, "Z")
  assert string.slice(ts, 10, 1) == "T"
  assert string.slice(ts, 19, 1) == "."
}

/// Control characters are escaped as JSON requires.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn json_escape_test() {
  assert log.json_escape("a\\b\"c\r\n\u{01}\u{1F}ż")
    == "a\\\\b\\\"c\\r\\n\\u0001\\u001fż"
}

/// A valid traceparent gives its trace and span identifiers.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn trace_valid_test() {
  assert trace.parse(Some(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    ))
    == Some(trace.TraceContext(
      "4bf92f3577b34da6a3ce929d0e0e4736",
      "00f067aa0ba902b7",
    ))
}

/// Invalid traceparent values are ignored.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn trace_invalid_test() {
  let invalid = [
    "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    "00-00000000000000000000000000000000-00f067aa0ba902b7-01",
    "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",
    "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01",
    "00-4bf92f3577b34da6a3ce929d0e0e473-00f067aa0ba902b7-01",
    "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7",
    "0x-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    "",
  ]
  list.each(invalid, fn(value) {
    assert trace.parse(Some(value)) == None
  })
  assert trace.parse(None) == None
}

/// The exposition lists every counter, zeros included.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn metrics_render_test() {
  let text =
    metrics.new(7, "0.1.0")
    |> metrics.count(metrics.Next, metrics.Failed)
    |> metrics.render
  assert string.starts_with(
    text,
    "# HELP digit_requests_total Requests answered by the digit service.\n"
      <> "# TYPE digit_requests_total counter\n"
      <> "digit_requests_total{digit=\"7\",endpoint=\"value\",outcome=\"ok\"} 0\n",
  )
  assert string.contains(
    text,
    "digit_requests_total{digit=\"7\",endpoint=\"next\",outcome=\"error\"} 1\n",
  )
  assert string.ends_with(
    text,
    "# TYPE digit_build_info gauge\n"
      <> "digit_build_info{digit=\"7\",version=\"0.1.0\"} 1\n",
  )
}

/// A process that waits until it is killed.
///
/// Parameters: none. Returns: its pid. Errors: none. Side Effects: spawns
/// an unlinked process. Complexity: O(1). Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `sleeper()`.
fn sleeper() -> process.Pid {
  process.spawn_unlinked(fn() { process.sleep_forever() })
}

/// Admit a given process (as a connection would admit itself).
///
/// Parameters: `subject` — the tracker; `pid` — the process. Returns:
/// True when admitted. Errors: none. Side Effects: a round trip.
/// Complexity: O(1). Thread Safety: safe. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `admit_pid(tracker, pid)`.
fn admit_pid(
  subject: process.Subject(tracker.Message),
  pid: process.Pid,
) -> Bool {
  let reply_to = process.new_subject()
  process.send(subject, tracker.Admit(pid, reply_to))
  let assert Ok(admitted) = process.receive(reply_to, 1000)
  admitted
}

/// At most max_connections are admitted; an ended one frees its slot.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn tracker_limit_test() {
  let assert Ok(subject) = tracker.start()
  let pids =
    list.map(list.repeat(Nil, tracker.max_connections), fn(_) { sleeper() })
  assert list.all(pids, admit_pid(subject, _))
  let extra = sleeper()
  assert !admit_pid(subject, extra)
  let assert [first, ..] = pids
  process.kill(first)
  process.sleep(20)
  assert tracker.count(subject) == #(tracker.max_connections - 1, 0)
  assert admit_pid(subject, extra)
  list.each([extra, ..pids], process.kill)
}

/// A stop kills idle connections, waits for busy ones and refuses more.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn tracker_stop_test() {
  let assert Ok(subject) = tracker.start()
  let idle = sleeper()
  let busy = sleeper()
  assert admit_pid(subject, idle)
  assert admit_pid(subject, busy)
  process.send(subject, tracker.Busy(busy))
  let stopper = process.new_subject()
  process.spawn(fn() {
    tracker.stop(subject)
    process.send(stopper, Nil)
  })
  process.sleep(50)
  assert !process.is_alive(idle)
  assert process.receive(stopper, 0) == Error(Nil)
  assert !tracker.keep(subject)
  assert !admit_pid(subject, sleeper())
  process.send(subject, tracker.Idle(busy))
  let assert Ok(Nil) = process.receive(stopper, 1000)
  process.kill(busy)
}

/// SIGTERM events reach the subject; other events do not.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn signal_handler_test() {
  let subject = process.new_subject()
  let assert Ok(state) = signal.init(subject)
  let assert Ok(_) =
    signal.handle_event(atom.to_dynamic(atom.create("sighup")), state)
  assert process.receive(subject, 0) == Error(Nil)
  let assert Ok(_) =
    signal.handle_event(atom.to_dynamic(atom.create("sigterm")), state)
  assert process.receive(subject, 0) == Ok(Nil)
  let assert Ok(_) =
    signal.handle_info(atom.to_dynamic(atom.create("x")), state)
  let #(ok, Nil, _) =
    signal.handle_call(atom.to_dynamic(atom.create("x")), state)
  assert atom.to_string(ok) == "ok"
}
