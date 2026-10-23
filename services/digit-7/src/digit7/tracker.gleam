//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/tracker.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         The connection tracker: admits at most
////                  `max_connections` connection processes, knows which of
////                  them are answering a request and drains them on stop.
//// Related Docs:    services/digit-7/src/digit7/server.gleam, ADR-0029
////
//// Connection bookkeeping of the digit-7 HTTP server, in one OTP actor.
////
//// Every connection process asks to be admitted before it reads a
//// request. The tracker monitors it, so a connection that ends for any
//// reason, a crash included, frees its slot. On stop the tracker refuses
//// new connections, kills the idle ones (which closes their sockets) and
//// answers the caller once the busy ones have finished or after
//// `drain_timeout_ms`.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

/// Largest number of open connections; one more is closed at once.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
pub const max_connections = 256

/// Milliseconds a stop waits for the requests being answered.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub const drain_timeout_ms = 5000

/// A message to the tracker.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type Message {
  /// Admit a connection process; replies False when the limit is reached
  /// or the server is stopping.
  Admit(pid: Pid, reply_to: Subject(Bool))
  /// A connection process started answering a request.
  Busy(pid: Pid)
  /// A connection process sent its reply and waits for the next request.
  Idle(pid: Pid)
  /// Whether connections may stay open: replies False once stopping.
  Keep(reply_to: Subject(Bool))
  /// Stop: refuse new connections, kill idle ones, reply when drained.
  Stop(reply_to: Subject(Nil))
  /// The drain deadline of a stop has passed.
  Deadline
  /// A monitored connection process ended.
  Ended(down: process.Down)
  /// Ask for the number of connections and of busy ones.
  Count(reply_to: Subject(#(Int, Int)))
}

/// The state of the tracker.
///
/// Thread Safety: owned by the tracker process. Owner: AEC.
/// Since: digit-7 0.1.0.
pub type State {
  /// Open connections (True when busy), the stop flag, the caller
  /// waiting for the drain and the tracker's own subject.
  State(
    connections: Dict(Pid, Bool),
    stopping: Bool,
    waiting: Option(Subject(Nil)),
    self: Subject(Message),
  )
}

/// The number of busy connections.
///
/// Parameters: `state` — the state. Returns: the count. Errors: none.
/// Side Effects: none. Complexity: O(n). Thread Safety: pure. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `busy_count(state) == 0`.
fn busy_count(state: State) -> Int {
  dict.fold(state.connections, 0, fn(count, _, busy) {
    case busy {
      True -> count + 1
      False -> count
    }
  })
}

/// Answer a waiting stop once no connection is busy.
///
/// Parameters: `state` — the state. Returns: the state, with `waiting`
/// cleared when it was answered. Errors: none. Side Effects: may send
/// the stop reply. Complexity: O(n). Thread Safety: tracker process.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `release(state)`.
fn release(state: State) -> State {
  case state.waiting, busy_count(state) {
    Some(reply_to), 0 -> {
      process.send(reply_to, Nil)
      State(..state, waiting: None)
    }
    _, _ -> state
  }
}

/// Handle one message of the tracker.
///
/// Parameters: `state` — the state; `message` — the message.
/// Returns: the next state. Errors: none. Side Effects: monitors and
/// kills connection processes; sends replies. Complexity: O(n) for a
/// stop, O(log n) otherwise. Thread Safety: tracker process. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `on_message(state, Busy(pid))`.
fn on_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Admit(pid, reply_to) -> {
      let admitted =
        !state.stopping && dict.size(state.connections) < max_connections
      process.send(reply_to, admitted)
      case admitted {
        False -> actor.continue(state)
        True -> {
          let _ = process.monitor(pid)
          actor.continue(
            State(
              ..state,
              connections: dict.insert(state.connections, pid, False),
            ),
          )
        }
      }
    }
    Busy(pid) ->
      actor.continue(
        State(..state, connections: dict.insert(state.connections, pid, True)),
      )
    Idle(pid) ->
      State(..state, connections: dict.insert(state.connections, pid, False))
      |> release
      |> actor.continue
    Keep(reply_to) -> {
      process.send(reply_to, !state.stopping)
      actor.continue(state)
    }
    Stop(reply_to) -> {
      dict.each(state.connections, fn(pid, busy) {
        case busy {
          True -> Nil
          False -> process.kill(pid)
        }
      })
      process.send_after(state.self, drain_timeout_ms, Deadline)
      State(..state, stopping: True, waiting: Some(reply_to))
      |> release
      |> actor.continue
    }
    Deadline -> {
      case state.waiting {
        Some(reply_to) -> process.send(reply_to, Nil)
        None -> Nil
      }
      actor.continue(State(..state, waiting: None))
    }
    Ended(process.ProcessDown(pid:, ..)) ->
      State(..state, connections: dict.delete(state.connections, pid))
      |> release
      |> actor.continue
    Ended(process.PortDown(..)) -> actor.continue(state)
    Count(reply_to) -> {
      process.send(reply_to, #(dict.size(state.connections), busy_count(state)))
      actor.continue(state)
    }
  }
}

/// Start the tracker.
///
/// Parameters: none. Returns: the tracker's subject.
/// Errors: `actor.StartError` when the process cannot start.
/// Side Effects: spawns a process linked to the caller.
/// Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `start()`.
pub fn start() -> Result(Subject(Message), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_monitors(Ended)
    State(connections: dict.new(), stopping: False, waiting: None, self:)
    |> actor.initialised
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(on_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

/// Ask the tracker to admit the calling process as a connection.
///
/// Parameters: `tracker` — the tracker. Returns: True when admitted.
/// Errors: none (False when the tracker does not answer in 1 s).
/// Side Effects: a round trip; the tracker monitors the caller.
/// Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `admit(tracker)`.
pub fn admit(tracker: Subject(Message)) -> Bool {
  let reply_to = process.new_subject()
  process.send(tracker, Admit(process.self(), reply_to))
  result.unwrap(process.receive(reply_to, 1000), False)
}

/// Tell the tracker that the calling connection answers a request.
///
/// Parameters: `tracker` — the tracker. Returns: Nil. Errors: none.
/// Side Effects: sends a message. Complexity: O(1). Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `busy(tracker)`.
pub fn busy(tracker: Subject(Message)) -> Nil {
  process.send(tracker, Busy(process.self()))
}

/// Tell the tracker that the calling connection sent its reply.
///
/// Description: an idle connection is closed at once by a stop; a busy
/// one is waited for.
/// Parameters: `tracker` — the tracker. Returns: Nil. Errors: none.
/// Side Effects: sends a message. Complexity: O(1). Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `idle(tracker)`.
pub fn idle(tracker: Subject(Message)) -> Nil {
  process.send(tracker, Idle(process.self()))
}

/// Whether connections may stay open after the current reply.
///
/// Parameters: `tracker` — the tracker. Returns: True while the server
/// runs, False once it is stopping (or when the tracker does not answer
/// in 1 s). Errors: none. Side Effects: a round trip.
/// Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `keep(tracker)`.
pub fn keep(tracker: Subject(Message)) -> Bool {
  let reply_to = process.new_subject()
  process.send(tracker, Keep(reply_to))
  result.unwrap(process.receive(reply_to, 1000), False)
}

/// Stop the tracker's connections and wait for the busy ones.
///
/// Parameters: `tracker` — the tracker. Returns: Nil once no connection
/// is busy, or after `drain_timeout_ms`. Errors: none. Side Effects:
/// kills idle connection processes. Complexity: O(n).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `stop(tracker)`.
pub fn stop(tracker: Subject(Message)) -> Nil {
  let reply_to = process.new_subject()
  process.send(tracker, Stop(reply_to))
  let _ = process.receive(reply_to, drain_timeout_ms + 1000)
  Nil
}

/// The number of open and of busy connections.
///
/// Parameters: `tracker` — the tracker. Returns: `#(open, busy)`;
/// `#(-1, -1)` when the tracker does not answer in 1 s. Errors: none.
/// Side Effects: a round trip. Complexity: O(n). Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `count(tracker)`.
pub fn count(tracker: Subject(Message)) -> #(Int, Int) {
  let reply_to = process.new_subject()
  process.send(tracker, Count(reply_to))
  result.unwrap(process.receive(reply_to, 1000), #(-1, -1))
}
