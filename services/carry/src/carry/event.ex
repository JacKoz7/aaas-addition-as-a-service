# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Event
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Builds the event aaas.carry.propagated.v1 in the event
#                  envelope of ADR-0013.
# Related Docs:    contracts/events/aaas.carry.propagated.v1.schema.json,
#                  contracts/events/envelope.v1.schema.json, ADR-0013

defmodule Carry.Event do
  @moduledoc """
  The event `aaas.carry.propagated.v1`.

  **Description:** one event per recorded call, with the envelope fields
  in the order of the schema and the payload `digits`, `position` and
  `result`. The JSON text is built once and stored with the call, so a
  retried call republishes exactly the same bytes.

  **Business Justification:** the audit trail of the carries
  (`CLAUDE.md` 4.2); the schema registry validates the same contract from
  P3.1.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Publisher`,
  `contracts/events/aaas.carry.propagated.v1.schema.json`.
  """

  @doc """
  The topic of the event.

  **Parameters:** none.

  **Returns:** `String.t()`; `"aaas.carry.propagated.v1"`.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(1).

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** one place names the topic of
  `contracts/events/topics.psv`.

  **Example:**

      iex> Carry.Event.topic()
      "aaas.carry.propagated.v1"

  **See Also:** `build/6`.
  """
  @spec topic() :: String.t()
  def topic, do: "aaas.carry.propagated.v1"

  @doc """
  Builds the JSON text of one event.

  **Parameters:**
  - `event_id` — `String.t()`; a new UUIDv7.
  - `millis` — integer; Unix time in milliseconds of `occurredAt`.
  - `task_id` — `String.t()`; the task (UUIDv7).
  - `trace` — `t:Carry.Trace.t/0`; the span of this call.
  - `request` — `{digits, position}`; the request.
  - `result` — list of digits; the digits after the carry.

  **Returns:** `String.t()`; the event as compact JSON.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(d) for d digits.

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the producer side of the contract.

  **Example:**

      iex> trace = %Carry.Trace{trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "b1c2d3e4f5a60718", flags: "01"}
      iex> Carry.Event.build("018f3c2e-7b1a-7c3d-9f00-000000000030", 1_760_616_001_250,
      ...>   "018f3c2e-7b1a-7c3d-9f00-0000000000aa", trace, {[0, 1], 1}, [0, 2])
      ~s({"eventId":"018f3c2e-7b1a-7c3d-9f00-000000000030","type":"aaas.carry.propagated","version":1,"occurredAt":"2025-10-16T12:00:01.250Z","producer":"carry","taskId":"018f3c2e-7b1a-7c3d-9f00-0000000000aa","traceparent":"00-4bf92f3577b34da6a3ce929d0e0e4736-b1c2d3e4f5a60718-01","payload":{"digits":[0,1],"position":1,"result":[0,2]}})

  **See Also:** `topic/0`, `Carry.Log.timestamp/1`.
  """
  @spec build(String.t(), integer(), String.t(), Carry.Trace.t(), {[0..9], non_neg_integer()}, [
          0..9
        ]) ::
          String.t()
  def build(event_id, millis, task_id, trace, {digits, position}, result) do
    object(
      eventId: event_id,
      type: "aaas.carry.propagated",
      version: 1,
      occurredAt: Carry.Log.timestamp(millis * 1000),
      producer: "carry",
      taskId: task_id,
      traceparent: Carry.Trace.render(trace),
      payload: {:object, [digits: digits, position: position, result: result]}
    )
    |> IO.iodata_to_binary()
  end

  # A JSON object whose keys keep their order.
  #
  # Parameters:
  #   - pairs: keyword list; a value {:object, pairs} is a nested object.
  #
  # Returns: iodata.
  #
  # Errors: none. Side Effects: none. Complexity: O(n).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: object(a: 1, b: {:object, [c: 2]}) is {"a":1,"b":{"c":2}}.
  defp object(pairs) do
    body =
      Enum.map_intersperse(pairs, ",", fn
        {key, {:object, nested}} ->
          [JSON.encode_to_iodata!(Atom.to_string(key)), ":", object(nested)]

        {key, value} ->
          [JSON.encode_to_iodata!(Atom.to_string(key)), ":", JSON.encode_to_iodata!(value)]
      end)

    ["{", body, "}"]
  end
end
