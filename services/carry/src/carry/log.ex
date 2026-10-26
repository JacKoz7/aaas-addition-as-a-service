# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Log
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Formatter of the Erlang :logger default handler: one JSON
#                  object per line with the fields of CLAUDE.md 6.1, for the
#                  service's own messages and those of the libraries.
# Related Docs:    CLAUDE.md 6.1, services/carry/docs/RUNBOOK.md

defmodule Carry.Log do
  @moduledoc """
  JSON log lines on stdout.

  **Description:** every log event becomes one line with the fields `ts`
  (UTC, milliseconds), `level` (`debug`, `info`, `warn` or `error`),
  `service`, `msg`, `taskId`, `traceId` and `spanId` (`null` when the
  event has none), followed by the entries of the metadata key `:fields`
  (a keyword list). The service's own messages set the metadata keys
  `:task_id`, `:trace_id`, `:span_id` and `:fields`; messages of the
  libraries (brod, ranch, the gRPC server) are rendered with their own
  report callback, so they are JSON lines too.

  **Business Justification:** logs are collected and searched by field
  (Loki from P7.1); a line that is not JSON would be lost to the search.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `install/2`, Erlang `:logger` formatter behaviour.
  """

  @doc """
  Installs the formatter on the default handler and sets the level.

  **Parameters:**
  - `service` — `String.t()`; the value of the `service` field.
  - `level` — `:debug`, `:info`, `:warning` or `:error`; the lowest level
    logged.

  **Returns:** `:ok`.

  **Errors:** `MatchError` when the default handler does not exist.

  **Side Effects:** changes the global `:logger` configuration.

  **Complexity:** O(1).

  **Thread Safety:** call once at start-up.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** every line after start-up is JSON.

  **Example:** `Carry.Log.install("carry", :info)` at start-up (changes
  global state, so not run as a doctest).

  **See Also:** `format/2`.
  """
  @spec install(String.t(), :debug | :info | :warning | :error) :: :ok
  def install(service, level) do
    :ok = :logger.update_handler_config(:default, :formatter, {__MODULE__, %{service: service}})
    :ok = :logger.update_handler_config(:default, :level, :all)
    :ok = :logger.set_primary_config(:level, level)
    Logger.configure(level: level)
  end

  @doc """
  Formats one log event (callback of the `:logger` formatter behaviour).

  **Parameters:**
  - `event` — `:logger.log_event()`; with `level`, `msg` and `meta`.
  - `config` — map with the key `:service`.

  **Returns:** `iodata()`; one JSON object and a newline.

  **Errors:** none: a message that cannot be rendered is replaced by its
  `inspect/1` form.

  **Side Effects:** none.

  **Complexity:** O(n) in the size of the message.

  **Thread Safety:** pure; called by the handler in the logging process.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the line format of `CLAUDE.md` 6.1.

  **Example:**

      iex> event = %{level: :info, msg: {:string, "carry started"}, meta: %{time: 0, fields: [grpcPort: 9090]}}
      iex> IO.iodata_to_binary(Carry.Log.format(event, %{service: "carry"}))
      ~s({"ts":"1970-01-01T00:00:00.000Z","level":"info","service":"carry","msg":"carry started","taskId":null,"traceId":null,"spanId":null,"grpcPort":9090}\\n)

  **See Also:** `install/2`.
  """
  @spec format(:logger.log_event(), map()) :: iodata()
  def format(%{level: level, msg: msg, meta: meta}, config) do
    fields =
      [
        ts: timestamp(Map.get(meta, :time, :os.system_time(:microsecond))),
        level: level_name(level),
        service: Map.get(config, :service, "carry"),
        msg: msg |> message(meta) |> String.trim_trailing(),
        taskId: Map.get(meta, :task_id),
        traceId: Map.get(meta, :trace_id),
        spanId: Map.get(meta, :span_id)
      ] ++ List.wrap(Map.get(meta, :fields, []))

    body =
      Enum.map_intersperse(fields, ",", fn {key, value} ->
        [encode(Atom.to_string(key)), ":", encode(value)]
      end)

    ["{", body, "}\n"]
  end

  @doc """
  Formats a `:logger` timestamp as the UTC text of the envelope.

  **Parameters:**
  - `microseconds` — integer; microseconds since the Unix epoch.

  **Returns:** `String.t()`; `YYYY-MM-DDTHH:MM:SS.sssZ`.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(1).

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** log lines and events use the same instant
  format (`contracts/events/envelope.v1.schema.json`).

  **Example:**

      iex> Carry.Log.timestamp(1_760_616_001_250_999)
      "2025-10-16T12:00:01.250Z"

  **See Also:** `Carry.Event.build/6`.
  """
  @spec timestamp(integer()) :: String.t()
  def timestamp(microseconds) do
    microseconds
    |> div(1000)
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_iso8601()
  end

  # The level names of CLAUDE.md 6.1.
  #
  # Parameters:
  #   - level: a :logger level.
  #
  # Returns: String.t(); "debug", "info", "warn" or "error".
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: level_name(:notice) returns "info".
  defp level_name(:debug), do: "debug"
  defp level_name(level) when level in [:info, :notice], do: "info"
  defp level_name(:warning), do: "warn"
  defp level_name(_), do: "error"

  # Renders the message of a log event as text.
  #
  # Description: strings are used as they are; reports use the report
  # callback of the event when it has one, and format strings are
  # expanded; anything else (or a failing callback) becomes inspect/1.
  #
  # Parameters:
  #   - msg: the msg of a :logger event.
  #   - meta: its metadata.
  #
  # Returns: String.t(); format/2 trims its trailing newline.
  #
  # Errors: none (rescued). Side Effects: none. Complexity: O(n).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: message({:string, ~c"x"}, %{}) returns "x".
  defp message({:string, text}, _meta), do: IO.chardata_to_string(text)

  defp message({:report, report}, %{report_cb: callback}) when is_function(callback, 1) do
    {format, args} = callback.(report)
    message({format, args}, %{})
  rescue
    _ -> inspect(report)
  end

  defp message({:report, report}, _meta), do: inspect(report)

  defp message({format, args}, _meta) do
    format |> :io_lib.format(args) |> IO.chardata_to_string()
  rescue
    _ -> inspect({format, args})
  end

  # Encodes one field value as JSON.
  #
  # Parameters:
  #   - value: term; strings, numbers, booleans, nil and lists or maps of
  #     them are encoded natively, anything else as its inspect/1 text.
  #
  # Returns: iodata.
  #
  # Errors: none. Side Effects: none. Complexity: O(n).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: encode(nil) returns "null".
  defp encode(value) do
    JSON.encode_to_iodata!(value)
  rescue
    _ -> JSON.encode_to_iodata!(inspect(value))
  end
end
