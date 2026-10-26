# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Drain
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Counts the gRPC calls in progress, so a SIGTERM stops
#                  accepting connections and lets the running calls finish
#                  before the service exits.
# Related Docs:    CLAUDE.md 6.1 (graceful shutdown), Carry.Application

defmodule Carry.Drain do
  @moduledoc """
  Calls in progress and the graceful stop.

  **Description:** `track/1` runs a call while an atomic counter (in
  `:persistent_term`) counts it. On SIGTERM, `stop/2` suspends the gRPC
  listener (no new connection is accepted) and waits until the counter is
  0 or the timeout passed; the supervisor then stops the servers.

  **Business Justification:** a SIGTERM during an addition must not cut a
  propagation in half (`CLAUDE.md` 6.1: shutdown in at most 10 s); the
  caller would only retry it, but a finished call is cheaper.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Application.prep_stop/1`, `Carry.Grpc.Server`.
  """

  # The :persistent_term key of the counter.
  @key {__MODULE__, :in_progress}

  # Milliseconds between two looks at the counter while draining.
  @poll 20

  @doc """
  Creates the counter.

  **Parameters:** none.

  **Returns:** `:ok`.

  **Errors:** none.

  **Side Effects:** writes one `:persistent_term` entry.

  **Complexity:** O(1).

  **Thread Safety:** call once at start-up.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the counter must exist before the first
  call.

  **Example:** `Carry.Drain.init()` in `Carry.Application.start/2`.

  **See Also:** `track/1`.
  """
  @spec init() :: :ok
  def init, do: :persistent_term.put(@key, :counters.new(1, [:atomics]))

  @doc """
  Runs a call while counting it.

  **Parameters:**
  - `fun` — zero-arity function; the call.

  **Returns:** the result of `fun`.

  **Errors:** whatever `fun` raises, after the counter is decremented.

  **Side Effects:** those of `fun`; updates the counter.

  **Complexity:** O(1) besides `fun`.

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see the module documentation.

  **Example:**

      iex> Carry.Drain.init()
      iex> Carry.Drain.track(fn -> Carry.Drain.in_progress() end)
      1
      iex> Carry.Drain.in_progress()
      0

  **See Also:** `stop/2`.
  """
  @spec track((-> result)) :: result when result: term()
  def track(fun) do
    counter = :persistent_term.get(@key)
    :counters.add(counter, 1, 1)

    try do
      fun.()
    after
      :counters.sub(counter, 1, 1)
    end
  end

  @doc """
  The number of calls in progress.

  **Parameters:** none.

  **Returns:** non-negative integer.

  **Errors:** `ArgumentError` before `init/0`.

  **Side Effects:** none.

  **Complexity:** O(1).

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** read by `stop/2` and logged at shutdown.

  **Example:** see `track/1`.

  **See Also:** `track/1`.
  """
  @spec in_progress() :: non_neg_integer()
  def in_progress, do: :counters.get(:persistent_term.get(@key), 1)

  @doc """
  Stops accepting gRPC connections and waits for the calls in progress.

  **Parameters:**
  - `listener` — term; the ranch listener of the gRPC server.
  - `timeout` — non-negative integer; milliseconds to wait at most.

  **Returns:** `:drained` when no call is in progress, or `:timeout`.

  **Errors:** none (a listener that does not exist is skipped).

  **Side Effects:** suspends the listener; sleeps while waiting.

  **Complexity:** O(timeout / 20 ms) looks at the counter.

  **Thread Safety:** call once, at shutdown.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the graceful shutdown of `CLAUDE.md` 6.1.

  **Example:** `Carry.Drain.stop("Carry.Grpc.Endpoint", 5_000)`.

  **See Also:** `Carry.Application.prep_stop/1`.
  """
  @spec stop(term(), non_neg_integer()) :: :drained | :timeout
  def stop(listener, timeout) do
    try do
      :ranch.suspend_listener(listener)
    catch
      _kind, _reason -> :ok
    end

    wait(System.monotonic_time(:millisecond) + timeout)
  end

  # Waits until no call is in progress or the deadline passed.
  #
  # Parameters:
  #   - deadline: integer; monotonic milliseconds.
  #
  # Returns: :drained or :timeout.
  #
  # Errors: none. Side Effects: sleeps. Complexity: O(waiting / 20 ms).
  # Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: wait(now) returns :drained when nothing runs.
  defp wait(deadline) do
    cond do
      in_progress() == 0 ->
        :drained

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        Process.sleep(@poll)
        wait(deadline)
    end
  end
end
