# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Propagation
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         One Propagate call end to end: validation, the
#                  propagation log, the digit services, the event and the
#                  outcome metrics.
# Related Docs:    services/carry/README.md (Processing of one call),
#                  contracts/proto/aaas/carry/v1/carry.proto, ADR-0032

defmodule Carry.Propagation do
  @moduledoc """
  Serves one `Propagate` call.

  **Description:** the steps are

  1. validate the request (`Carry.Core.validate/3`);
  2. look the call up in the propagation log; a recorded call (a retry)
     republishes its stored event and answers its stored result;
  3. otherwise propagate the carry through the digit services
     (`Carry.Core.propagate/3` with `Carry.Digits.next/3`);
  4. build the event and record the call; when a concurrent attempt
     recorded it first, its record wins;
  5. publish the recorded event and wait for the acknowledgement;
  6. answer the recorded result.

  The answer comes after both side effects, so a caller that saw success
  can rely on the audit trail; a failure after step 4 is repaired by the
  caller's retry, which republishes the same event (step 2).

  **Business Justification:** a carry is part of every successor call of
  a number ending in 9; it must be correct, auditable and safe to retry.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Grpc.Server`, `Carry.Store`, `Carry.Publisher`.
  """

  require Logger

  alias Carry.{Core, Digits, Event, Metrics, Publisher, Store, Trace, Uuid}

  # Milliseconds one call may take when the caller set no shorter
  # deadline (as the 1.8 s budget of successor, ADR-0016).
  @budget 1_800

  # Milliseconds to wait for the broker's acknowledgement at most.
  @publish_timeout 1_000

  @typedoc """
  The failure of a call, mapped to a gRPC status by the server:
  `:invalid_argument`, `:unavailable` or `:internal`, with a message.
  """
  @type failure :: {:invalid_argument | :unavailable | :internal, String.t()}

  @doc """
  Serves one call.

  **Parameters:**
  - `request` — map with `digits` (list of integers), `position` and
    `task_id`, as decoded from `PropagateRequest`.
  - `options` — keyword list: `:template` (`AAAS_DIGIT_URL_TEMPLATE`,
    required), `:traceparent` (the request header or `nil`) and
    `:remaining` (milliseconds left before the caller's deadline, or
    `:infinity`).

  **Returns:** `{:ok, result}` with the digits after the carry, or
  `{:error, failure}`.

  **Errors:** `{:error, {:invalid_argument, message}}` for a request that
  breaks the contract; `{:error, {:unavailable, message}}` when a digit
  service, Mnesia or the broker failed; `{:error, {:internal, message}}`
  when a digit service answered outside its contract.

  **Side Effects:** 0 to 7 digit service calls (each up to three HTTP
  attempts), one Mnesia transaction, one Kafka message; counts
  `carry_propagations_total` and observes
  `carry_propagation_duration_seconds`; logs at debug level on success
  and at warning level on failure, with the task and trace identifiers.

  **Complexity:** O(d) network calls for d digits.

  **Thread Safety:** safe for concurrent use; concurrent attempts of one
  call record and publish one event.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the implementation of
  `CarryService.Propagate`.

  **Example:** `Carry.Propagation.run(%{digits: [0, 9], position: 1,
  task_id: task_id}, template: "http://digit-{digit}:8080")` returns
  `{:ok, [0, 0, 1]}`.

  **See Also:** `Carry.Core.propagate/3`.
  """
  @spec run(
          %{digits: [non_neg_integer()], position: non_neg_integer(), task_id: String.t()},
          keyword()
        ) ::
          {:ok, [0..9]} | {:error, failure()}
  def run(%{digits: digits, position: position, task_id: task_id}, options) do
    started = System.monotonic_time(:microsecond)
    span = options |> Keyword.get(:traceparent) |> Trace.parse() |> Trace.child()
    # A malformed task identifier is not copied into the log lines.
    logged_task = if Uuid.v7?(task_id), do: task_id
    Logger.metadata(task_id: logged_task, trace_id: span.trace_id, span_id: span.span_id)

    deadline =
      System.monotonic_time(:millisecond) + budget(Keyword.get(options, :remaining, :infinity))

    outcome =
      with :ok <- invalid_argument(Core.validate(digits, position, task_id)),
           {:ok, entry, status} <-
             recorded_or_new({task_id, digits, position}, span, deadline, options),
           :ok <- publish(entry, deadline) do
        {:ok, entry, status}
      end

    finish(outcome, {digits, position}, started)
  end

  # Maps a validation failure to the failure of the call.
  #
  # Parameters:
  #   - result: :ok or {:error, message}.
  #
  # Returns: :ok or {:error, {:invalid_argument, message}}.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: invalid_argument({:error, "x"}) returns
  # {:error, {:invalid_argument, "x"}}.
  defp invalid_argument(:ok), do: :ok
  defp invalid_argument({:error, message}), do: {:error, {:invalid_argument, message}}

  # The recorded entry of a call, computing and recording it first when
  # the log has none.
  #
  # Parameters:
  #   - key: {task_id, digits, position}.
  #   - span: Trace.t(); the span of this call.
  #   - deadline: integer; monotonic milliseconds.
  #   - options: the options of run/2.
  #
  # Returns: {:ok, entry, :replayed | :ok} or {:error, failure}.
  #
  # Errors: see run/2. Side Effects: Mnesia reads and one transaction,
  # digit service calls. Complexity: O(d) network calls.
  # Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: for a retried call, returns {:ok, stored, :replayed} without
  # calling a digit service.
  defp recorded_or_new({task_id, digits, position} = key, span, deadline, options) do
    case Store.lookup(key) do
      {:ok, entry} ->
        {:ok, entry, :replayed}

      :none ->
        next = fn digit ->
          Digits.next(Keyword.fetch!(options, :template), digit,
            deadline: deadline,
            traceparent: Trace.render(span)
          )
        end

        with {:ok, result} <- compute(digits, position, next) do
          event_id = Uuid.generate()
          now = System.system_time(:millisecond)

          record(%{
            task_id: task_id,
            digits: digits,
            position: position,
            result: result,
            event_id: event_id,
            event: Event.build(event_id, now, task_id, span, {digits, position}, result),
            propagated_at: now,
            trace_id: span.trace_id
          })
        end

      {:error, reason} ->
        database_failure(reason)
    end
  end

  # Propagates the carry through the digit services.
  #
  # Parameters:
  #   - digits: the digits of the request.
  #   - position: the position of the carry.
  #   - next: Core.next_digit(); the digit service client.
  #
  # Returns: {:ok, result} or {:error, failure}.
  #
  # Errors: unavailable for an unreachable digit service, internal for an
  # answer outside the contract. Side Effects: digit service calls.
  # Complexity: O(d). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: compute([0, 9], 1, next) returns {:ok, [0, 0, 1]}.
  defp compute(digits, position, next) do
    case Core.propagate(digits, position, next) do
      {:ok, result, _calls} ->
        {:ok, result}

      {:error, {:unavailable, detail}} ->
        {:error, {:unavailable, detail}}

      {:error, {:invalid_answer, detail}} ->
        {:error, {:internal, detail}}

      {:error, :new_digit_carries} ->
        {:error, {:internal, "digit-0 answered a carry for the successor of 0"}}
    end
  end

  # Records a computed call in the propagation log.
  #
  # Parameters:
  #   - entry: Store.entry(); the computed call.
  #
  # Returns: {:ok, stored entry, :ok} or {:error, failure}.
  #
  # Errors: unavailable when Mnesia fails. Side Effects: one Mnesia
  # transaction. Complexity: O(1). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: record(entry) returns {:ok, entry, :ok} for a new call.
  defp record(entry) do
    case Store.record(entry) do
      {:ok, _created_or_existing, stored} -> {:ok, stored, :ok}
      {:error, reason} -> database_failure(reason)
    end
  end

  # Publishes the event of an entry within the deadline.
  #
  # Parameters:
  #   - entry: Store.entry().
  #   - deadline: integer; monotonic milliseconds.
  #
  # Returns: :ok or {:error, {:unavailable, message}}.
  #
  # Errors: see return. Side Effects: one Kafka message; counts
  # carry_dependency_failures_total{dependency="broker"} on failure.
  # Complexity: O(1). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: publish(entry, deadline) returns :ok with Redpanda up.
  defp publish(entry, deadline) do
    timeout = min(@publish_timeout, deadline - System.monotonic_time(:millisecond))

    with true <- timeout > 0 || {:error, :deadline_exceeded},
         :ok <- publisher().publish(entry.task_id, entry.event, timeout) do
      :ok
    else
      {:error, reason} ->
        Metrics.count("carry_dependency_failures_total", dependency: "broker")
        {:error, {:unavailable, "broker: #{inspect(reason)}"}}
    end
  end

  # The module that publishes events: Carry.Publisher, or the fake of the
  # unit tests (application environment :carry, :publisher).
  #
  # Parameters: none.
  #
  # Returns: module; it exports publish/3 like Carry.Publisher.
  #
  # Errors: none. Side Effects: reads the application environment.
  # Complexity: O(1). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: publisher() returns Carry.Publisher in the release.
  defp publisher, do: Application.get_env(:carry, :publisher, Publisher)

  # The failure of a call whose Mnesia access failed.
  #
  # Parameters:
  #   - reason: term; the Mnesia error.
  #
  # Returns: {:error, {:unavailable, message}}.
  #
  # Errors: none. Side Effects: counts
  # carry_dependency_failures_total{dependency="database"}.
  # Complexity: O(1). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: database_failure(:no_exists) returns
  # {:error, {:unavailable, "database: :no_exists"}}.
  defp database_failure(reason) do
    Metrics.count("carry_dependency_failures_total", dependency: "database")
    {:error, {:unavailable, "database: #{inspect(reason)}"}}
  end

  # Counts, times and logs the outcome of a call.
  #
  # Parameters:
  #   - outcome: {:ok, entry, :ok | :replayed} or {:error, failure}.
  #   - request: {digits, position}; for the log line.
  #   - started: integer; monotonic microseconds at the start.
  #
  # Returns: {:ok, result} or {:error, failure}.
  #
  # Errors: none. Side Effects: metrics and one log line.
  # Complexity: O(1). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: finish({:ok, entry, :ok}, {[0, 9], 1}, started) returns
  # {:ok, entry.result}.
  defp finish(outcome, {digits, position}, started) do
    Metrics.observe(System.monotonic_time(:microsecond) - started)

    case outcome do
      {:ok, entry, status} ->
        Metrics.count("carry_propagations_total", outcome: Atom.to_string(status))

        Logger.debug("carry propagated",
          fields: [
            digits: digits,
            position: position,
            result: entry.result,
            outcome: Atom.to_string(status)
          ]
        )

        {:ok, entry.result}

      {:error, {code, message}} ->
        Metrics.count("carry_propagations_total", outcome: Atom.to_string(code))

        Logger.warning("carry not propagated",
          fields: [code: Atom.to_string(code), detail: message]
        )

        {:error, {code, message}}
    end
  end

  # The milliseconds a call may use.
  #
  # Parameters:
  #   - remaining: non-negative integer or :infinity; the caller's
  #     remaining deadline.
  #
  # Returns: non-negative integer; at most the 1.8 s budget.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: budget(:infinity) returns 1800; budget(500) returns 500.
  defp budget(:infinity), do: @budget
  defp budget(remaining), do: min(remaining, @budget)
end
