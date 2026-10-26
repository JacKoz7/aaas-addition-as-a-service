# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          tests/support/fakes.ex
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Test doubles of the dependencies of carry: digit services
#                  served by one local Cowboy listener, and a publisher that
#                  keeps the events in memory and writes them for the schema
#                  check of the test stage.
# Related Docs:    tests/, scripts/validate-events.py (--events)

defmodule Carry.Test.FakeDigits do
  @moduledoc """
  Fake digit services on one local HTTP port.

  **Description:** `GET /<N>/next` answers the contract of `digit-N` from
  a successor table, so the template `http://127.0.0.1:<port>/{digit}`
  reaches all ten. `script/2` makes the next answers of one digit come
  from a list: `{status, body}`, `:sleep` (no answer within an attempt)
  or `:default`. Every request is counted.

  **Business Justification:** the carry logic and the retries are tested
  without the ten real services.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Digits`.
  """

  @behaviour :cowboy_handler

  # The successor of each digit, as seeded in the digit services.
  @successors {1, 2, 3, 4, 5, 6, 7, 8, 9, 0}

  @doc """
  Starts the listener on a free port and returns the URL template.

  **Parameters:** none.

  **Returns:** `String.t()`; the template for `Carry.Digits.next/3`.

  **Errors:** raises when the listener cannot start.

  **Side Effects:** creates the ETS table `:fake_digits`; opens a port.

  **Complexity:** O(1).

  **Thread Safety:** call once per test module.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see the module documentation.

  **Example:** `template = Carry.Test.FakeDigits.start()`.

  **See Also:** `script/2`.
  """
  @spec start() :: String.t()
  def start do
    if :ets.whereis(:fake_digits) == :undefined do
      :ets.new(:fake_digits, [:named_table, :public, :set])
    end

    :ets.delete_all_objects(:fake_digits)
    dispatch = :cowboy_router.compile([{:_, [{"/:digit/next", __MODULE__, nil}]}])
    :cowboy.stop_listener(:fake_digits)
    {:ok, _} = :cowboy.start_clear(:fake_digits, [port: 0], %{env: %{dispatch: dispatch}})
    "http://127.0.0.1:#{:ranch.get_port(:fake_digits)}/{digit}"
  end

  @doc """
  Forgets the scripts and request counts.

  **Parameters:** none.

  **Returns:** `true`.

  **Errors:** none.

  **Side Effects:** clears the ETS table.

  **Complexity:** O(n).

  **Thread Safety:** tests run sequentially.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** each test starts with healthy digits.

  **Example:** `reset()` in a setup block.

  **See Also:** `start/0`.
  """
  @spec reset() :: true
  def reset, do: :ets.delete_all_objects(:fake_digits)

  @doc """
  Sets the next answers of one digit.

  **Parameters:**
  - `digit` — integer in `0..9`.
  - `answers` — list of `{status, body}`, `:sleep` or `:default`.

  **Returns:** `true`.

  **Errors:** none.

  **Side Effects:** writes the ETS table.

  **Complexity:** O(1).

  **Thread Safety:** tests using it must not run concurrently.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** failures of a digit service are scripted.

  **Example:** `script(9, [{503, "{}"}, :default])`.

  **See Also:** `requests/1`.
  """
  @spec script(0..9, list()) :: true
  def script(digit, answers), do: :ets.insert(:fake_digits, {{:script, digit}, answers})

  @doc """
  The number of requests one digit received.

  **Parameters:**
  - `digit` — integer in `0..9`.

  **Returns:** non-negative integer.

  **Errors:** none.

  **Side Effects:** reads the ETS table.

  **Complexity:** O(1).

  **Thread Safety:** safe.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** tests prove which digits were asked.

  **Example:** `requests(9)` is 1 after one carry from 9.

  **See Also:** `script/2`.
  """
  @spec requests(0..9) :: non_neg_integer()
  def requests(digit) do
    case :ets.lookup(:fake_digits, {:count, digit}) do
      [{_, count}] -> count
      [] -> 0
    end
  end

  @doc """
  Answers one request (callback of `:cowboy_handler`).

  **Parameters:**
  - `request` — `:cowboy_req.req()`.
  - `state` — `nil`.

  **Returns:** `{:ok, request, state}`.

  **Errors:** none.

  **Side Effects:** counts the request; may sleep 400 ms.

  **Complexity:** O(1).

  **Thread Safety:** safe.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see the module documentation.

  **Example:** `GET /d9/next` answers `{"digit":9,"next":0,"carry":true}`.

  **See Also:** `start/0`.
  """
  @impl true
  @spec init(:cowboy_req.req(), nil) :: {:ok, :cowboy_req.req(), nil}
  def init(request, state) do
    digit = String.to_integer(:cowboy_req.binding(:digit, request))
    :ets.update_counter(:fake_digits, {:count, digit}, 1, {{:count, digit}, 0})

    {status, body} =
      case next_answer(digit) do
        :default -> {200, contract(digit)}
        :sleep -> sleep_then(contract(digit))
        answer -> answer
      end

    {:ok, :cowboy_req.reply(status, %{"content-type" => "application/json"}, body, request), state}
  end

  # Waits longer than one attempt of Carry.Digits, then answers.
  #
  # Parameters:
  #   - body: String.t(); the answer.
  #
  # Returns: {200, body}.
  #
  # Errors: none. Side Effects: sleeps 400 ms. Complexity: O(1).
  # Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: sleep_then("{}") returns {200, "{}"} after 400 ms.
  defp sleep_then(body) do
    Process.sleep(400)
    {200, body}
  end

  # Pops the next scripted answer of a digit, :default when none is left.
  #
  # Parameters:
  #   - digit: 0..9.
  #
  # Returns: an answer of script/2.
  #
  # Errors: none. Side Effects: updates the ETS table. Complexity: O(1).
  # Thread Safety: tests run sequentially. Owner: Arithmetic Excellence
  # Center (AEC). Since: carry 0.1.0.
  #
  # Example: next_answer(9) returns :default without a script.
  defp next_answer(digit) do
    case :ets.lookup(:fake_digits, {:script, digit}) do
      [{key, [answer | rest]}] ->
        :ets.insert(:fake_digits, {key, rest})
        answer

      _ ->
        :default
    end
  end

  # The contract answer of a digit.
  #
  # Parameters:
  #   - digit: 0..9.
  #
  # Returns: String.t(); the JSON body of GET /next.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: contract(9) is {"digit":9,"next":0,"carry":true}.
  defp contract(digit) do
    ~s({"digit":#{digit},"next":#{elem(@successors, digit)},"carry":#{digit == 9}})
  end
end

defmodule Carry.Test.FakePublisher do
  @moduledoc """
  A publisher that keeps events in memory.

  **Description:** `publish/3` stores `{key, value}` in the ETS table
  `:fake_events` and writes the value to `$PRODUCED_DIR/<n>.json` when the
  variable is set, for `scripts/validate-events.py --events`. `fail/1`
  makes the next calls fail.

  **Business Justification:** the unit tests run without Redpanda and
  still check every event against its schema.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Publisher`.
  """

  @doc """
  Clears the stored events and failures.

  **Parameters:** none.

  **Returns:** `true`.

  **Errors:** none.

  **Side Effects:** creates or clears `:fake_events`.

  **Complexity:** O(n).

  **Thread Safety:** tests run sequentially.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** each test starts empty.

  **Example:** `reset()` in a setup block.

  **See Also:** `events/0`.
  """
  @spec reset() :: true
  def reset do
    if :ets.whereis(:fake_events) == :undefined do
      :ets.new(:fake_events, [:named_table, :public, :ordered_set])
    end

    :ets.delete_all_objects(:fake_events)
  end

  @doc """
  Makes the next `count` publications fail.

  **Parameters:**
  - `count` — non-negative integer.

  **Returns:** `true`.

  **Errors:** none.

  **Side Effects:** writes the ETS table.

  **Complexity:** O(1).

  **Thread Safety:** tests run sequentially.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** broker outages are tested.

  **Example:** `fail(1)`.

  **See Also:** `publish/3`.
  """
  @spec fail(non_neg_integer()) :: true
  def fail(count), do: :ets.insert(:fake_events, {:fail, count})

  @doc """
  Stores one event (same contract as `Carry.Publisher.publish/3`).

  **Parameters:**
  - `key` — `String.t()`.
  - `value` — `String.t()`.
  - `timeout` — positive integer (unused).

  **Returns:** `:ok`, or `{:error, :broker_down}` while failures remain.

  **Errors:** none.

  **Side Effects:** writes the ETS table and, with `PRODUCED_DIR`, a file.

  **Complexity:** O(n) in the value.

  **Thread Safety:** safe.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see the module documentation.

  **Example:** `publish(task_id, event, 1_000)`.

  **See Also:** `events/0`.
  """
  @spec publish(String.t(), String.t(), pos_integer()) :: :ok | {:error, :broker_down}
  def publish(key, value, _timeout) do
    case :ets.lookup(:fake_events, :fail) do
      [{:fail, count}] when count > 0 ->
        :ets.insert(:fake_events, {:fail, count - 1})
        {:error, :broker_down}

      _ ->
        id = System.unique_integer([:positive, :monotonic])
        :ets.insert(:fake_events, {{:event, id}, key, value})

        case System.get_env("PRODUCED_DIR") do
          nil ->
            :ok

          dir ->
            File.mkdir_p!(dir)
            File.write!(Path.join(dir, "carry-#{id}.json"), value)
        end

        :ok
    end
  end

  @doc """
  The stored events, oldest first.

  **Parameters:** none.

  **Returns:** list of `{key, value}`.

  **Errors:** none.

  **Side Effects:** reads the ETS table.

  **Complexity:** O(n).

  **Thread Safety:** safe.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** tests assert what was published.

  **Example:** `[{task_id, json}] = events()`.

  **See Also:** `publish/3`.
  """
  @spec events() :: [{String.t(), String.t()}]
  def events, do: for({{:event, _}, key, value} <- :ets.tab2list(:fake_events), do: {key, value})
end
