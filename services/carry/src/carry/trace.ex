# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Trace
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         W3C Trace Context: parses the caller's `traceparent` and
#                  derives the span of the carry service, so log lines and
#                  events join the caller's trace.
# Related Docs:    CLAUDE.md 6.1, https://www.w3.org/TR/trace-context/

defmodule Carry.Trace do
  @moduledoc """
  The trace context of one propagation.

  **Description:** the service exports no spans before phase 7 (P7.2). It
  continues the caller's trace: a valid incoming `traceparent` keeps its
  trace identifier and flags, and the service's own span gets a new
  random identifier; without one, a new trace is started.

  **Business Justification:** one addition can be followed across the 35
  services in the logs and in the `traceparent` field of every event.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Event`, `Carry.Log`.
  """

  @typedoc """
  A trace context: `trace_id` (32 lowercase hexadecimal digits, not all
  zero), `span_id` (16, not all zero) and `flags` (2).
  """
  @type t :: %__MODULE__{trace_id: String.t(), span_id: String.t(), flags: String.t()}

  @enforce_keys [:trace_id, :span_id, :flags]
  defstruct [:trace_id, :span_id, :flags]

  @doc """
  Parses a `traceparent` header value.

  **Description:** the value must be `version-traceid-spanid-flags` with 2,
  32, 16 and 2 lowercase hexadecimal digits; version `ff` and all-zero
  trace or span identifiers are invalid (W3C Trace Context, 3.2).

  **Parameters:**
  - `header` — `String.t()` or `nil`; the header value.

  **Returns:** `t()` or `nil` for an absent or invalid header.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(n) in the length of the header.

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** a malformed header must not put garbage into
  logs and events; it is ignored instead.

  **Example:**

      iex> Carry.Trace.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
      %Carry.Trace{trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "00f067aa0ba902b7", flags: "01"}
      iex> Carry.Trace.parse("garbage")
      nil

  **See Also:** `child/1`.
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse(header) when is_binary(header) do
    with [version, trace_id, span_id, flags] <- String.split(header, "-"),
         true <- hex?(version, 2, false) and version != "ff",
         true <- hex?(trace_id, 32, true) and hex?(span_id, 16, true) and hex?(flags, 2, false) do
      %__MODULE__{trace_id: trace_id, span_id: span_id, flags: flags}
    else
      _ -> nil
    end
  end

  def parse(nil), do: nil

  @doc """
  Derives the span of this service from the caller's context.

  **Parameters:**
  - `parent` — `t()` or `nil`; the parsed `traceparent` of the request.

  **Returns:** `t()`; the caller's trace identifier and flags with a new
  span identifier, or a new trace (flags `01`) when `parent` is `nil`.

  **Errors:** none.

  **Side Effects:** reads the cryptographic random generator.

  **Complexity:** O(1) time and memory.

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the event names the span that produced it.

  **Example:**

      iex> parent = Carry.Trace.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
      iex> child = Carry.Trace.child(parent)
      iex> {child.trace_id, child.flags, child.span_id != parent.span_id}
      {"4bf92f3577b34da6a3ce929d0e0e4736", "01", true}

  **See Also:** `render/1`.
  """
  @spec child(t() | nil) :: t()
  def child(%__MODULE__{} = parent), do: %{parent | span_id: random_hex(8)}
  def child(nil), do: %__MODULE__{trace_id: random_hex(16), span_id: random_hex(8), flags: "01"}

  @doc """
  Renders a context as a `traceparent` value (version `00`).

  **Parameters:**
  - `context` — `t()`.

  **Returns:** `String.t()`; 55 characters.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(1) time and memory.

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the `traceparent` field of the event
  envelope.

  **Example:**

      iex> Carry.Trace.render(%Carry.Trace{trace_id: String.duplicate("a", 32), span_id: String.duplicate("b", 16), flags: "01"})
      "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"

  **See Also:** `parse/1`.
  """
  @spec render(t()) :: String.t()
  def render(%__MODULE__{trace_id: trace_id, span_id: span_id, flags: flags}) do
    "00-#{trace_id}-#{span_id}-#{flags}"
  end

  # Whether a text is lowercase hexadecimal of a given length, optionally
  # not all zeros.
  #
  # Parameters:
  #   - part: String.t(); the text.
  #   - length: positive integer; the required number of characters.
  #   - non_zero?: boolean; require a digit other than `0`.
  #
  # Returns: boolean; true when the text qualifies.
  #
  # Errors: none. Side Effects: none. Complexity: O(length).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: hex?("0a", 2, false) is true; hex?("00", 2, true) is false.
  defp hex?(part, length, non_zero?) do
    byte_size(part) == length and part =~ ~r/\A[0-9a-f]+\z/ and
      (not non_zero? or part != String.duplicate("0", length))
  end

  # A random lowercase hexadecimal identifier that is not all zeros.
  #
  # Parameters:
  #   - bytes: positive integer; the number of random bytes.
  #
  # Returns: String.t(); 2 * bytes hexadecimal digits.
  #
  # Errors: none. Side Effects: reads the cryptographic random generator.
  # Complexity: O(bytes). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: random_hex(8) returns 16 digits such as "5f0e2c9a7b31d4e8".
  defp random_hex(bytes) do
    id = bytes |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    if id == String.duplicate("0", 2 * bytes), do: random_hex(bytes), else: id
  end
end
