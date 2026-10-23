//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/signal.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Delivery of SIGTERM to the main process as a message,
////                  so the service stops gracefully instead of being
////                  halted by the Erlang runtime's default handler.
//// Related Docs:    https://www.erlang.org/doc/apps/kernel/os.html#set_signal/2,
////                  CLAUDE.md 6.1, ADR-0029
////
//// SIGTERM handling of the digit-7 service.
////
//// The Erlang runtime receives OS signals in the `erl_signal_server` event
//// manager; its default handler answers SIGTERM with `init:stop()`. This
//// module replaces that handler with itself: `init` and `handle_event`
//// are `gen_event` callbacks (this module compiles to the Erlang module
//// `digit7@signal`), and a SIGTERM becomes a message on the subject given
//// to `install`.

import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Subject}

/// OS signals of `os:set_signal/2`.
///
/// Thread Safety: an immutable value. Owner: Arithmetic Excellence Center
/// (AEC). Since: digit-7 0.1.0.
type Signal {
  /// The Erlang atom `sigterm`.
  Sigterm
}

/// Actions of `os:set_signal/2`.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
type Action {
  /// The Erlang atom `handle`: deliver the signal to `erl_signal_server`.
  Handle
}

/// `os:set_signal/2`.
///
/// Parameters: `signal` — the signal; `action` — what the runtime does.
/// Returns: `ok`. Errors: none for SIGTERM. Side Effects: changes the
/// runtime's signal disposition. Complexity: O(1). Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `set_signal(Sigterm, Handle)`.
@external(erlang, "os", "set_signal")
fn set_signal(signal: Signal, action: Action) -> Dynamic

/// `gen_event:delete_handler/3`.
///
/// Parameters: `manager` — the event manager; `handler` — the handler
/// module; `args` — passed to its `terminate`. Returns: the handler's
/// result or `{error, module_not_found}`. Errors: as the result says.
/// Side Effects: removes the handler. Complexity: O(n).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `delete_handler(manager, default, [])`.
@external(erlang, "gen_event", "delete_handler")
fn delete_handler(manager: Atom, handler: Atom, args: List(Nil)) -> Dynamic

/// `gen_event:add_handler/3`.
///
/// Parameters: `manager` — the event manager; `handler` — the handler
/// module; `args` — passed to its `init`. Returns: `ok` or the error.
/// Errors: as the result says. Side Effects: installs the handler.
/// Complexity: O(n). Thread Safety: safe. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `add_handler(manager, module, subject)`.
@external(erlang, "gen_event", "add_handler")
fn add_handler(manager: Atom, handler: Atom, args: Subject(Nil)) -> Dynamic

/// Deliver SIGTERM to a subject instead of stopping the runtime.
///
/// Business Justification: graceful shutdown on SIGTERM in at most 10 s
/// (CLAUDE.md 6.1) needs the signal as a message: the main process then
/// drains the connections and halts by itself.
/// Parameters: `subject` — receives `Nil` on every SIGTERM; it belongs to
/// the calling process. Returns: Nil. Errors: none.
/// Side Effects: replaces the default handler `erl_signal_handler` of
/// `erl_signal_server` with this module. Complexity: O(1).
/// Thread Safety: call once, at start-up. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `install(process.new_subject())`.
pub fn install(subject: Subject(Nil)) -> Nil {
  let manager = atom.create("erl_signal_server")
  let _ = delete_handler(manager, atom.create("erl_signal_handler"), [])
  let _ = add_handler(manager, atom.create("digit7@signal"), subject)
  let _ = set_signal(Sigterm, Handle)
  Nil
}

/// `gen_event` callback: initialise the handler with the subject.
///
/// Parameters: `subject` — the subject given to `install`. Returns:
/// `{ok, Subject}` as `Ok(subject)`. Errors: none. Side Effects: none.
/// Complexity: O(1). Thread Safety: runs in `erl_signal_server`.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `init(subject)`.
pub fn init(subject: Subject(Nil)) -> Result(Subject(Nil), Nil) {
  Ok(subject)
}

/// `gen_event` callback: forward SIGTERM, ignore other signals.
///
/// Parameters: `event` — the signal atom; `subject` — the handler state.
/// Returns: `{ok, Subject}` as `Ok(subject)`. Errors: none.
/// Side Effects: sends `Nil` to the subject on SIGTERM.
/// Complexity: O(1). Thread Safety: runs in `erl_signal_server`.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `handle_event(sigterm, s)`.
pub fn handle_event(
  event: Dynamic,
  subject: Subject(Nil),
) -> Result(Subject(Nil), Nil) {
  case event == atom.to_dynamic(atom.create("sigterm")) {
    True -> process.send(subject, Nil)
    False -> Nil
  }
  Ok(subject)
}

/// `gen_event` callback: answer a call (none is ever made).
///
/// Parameters: `request` — ignored; `subject` — the handler state.
/// Returns: `{ok, nil, Subject}`. Errors: none. Side Effects: none.
/// Complexity: O(1). Thread Safety: runs in `erl_signal_server`.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `handle_call(request, s)`.
pub fn handle_call(
  request: Dynamic,
  subject: Subject(Nil),
) -> #(Atom, Nil, Subject(Nil)) {
  let _ = request
  #(atom.create("ok"), Nil, subject)
}

/// `gen_event` callback: ignore other messages to the event manager.
///
/// Parameters: `message` — ignored; `subject` — the handler state.
/// Returns: `{ok, Subject}`. Errors: none. Side Effects: none.
/// Complexity: O(1). Thread Safety: runs in `erl_signal_server`.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `handle_info(message, s)`.
pub fn handle_info(
  message: Dynamic,
  subject: Subject(Nil),
) -> Result(Subject(Nil), Nil) {
  let _ = message
  Ok(subject)
}
