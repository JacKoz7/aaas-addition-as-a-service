# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Uuid
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         UUIDv7 generation (event identifiers) and validation
#                  (task identifiers of gRPC requests), RFC 9562.
# Related Docs:    contracts/events/envelope.v1.schema.json, ADR-0013

defmodule Carry.Uuid do
  @moduledoc """
  UUIDv7 identifiers in the lowercase canonical text form.

  **Description:** `generate/0` builds a version 7 UUID from the current
  Unix time in milliseconds and 74 random bits; `from_parts/2` is the pure
  part, so its layout can be tested. `v7?/1` accepts exactly the pattern
  `uuidV7` of the event envelope.

  **Business Justification:** every event needs a time-ordered `eventId`,
  and a malformed `task_id` must be refused before it reaches the call
  log or an event (`contracts/proto/aaas/carry/v1/carry.proto`).

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Event`, ADR-0013.
  """

  # The envelope pattern `uuidV7` (contracts/events/envelope.v1.schema.json).
  @v7_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  @doc """
  Generates a new UUIDv7.

  **Parameters:** none.

  **Returns:** `String.t()`; a lowercase UUIDv7 whose first 48 bits are the
  current Unix time in milliseconds.

  **Errors:** none.

  **Side Effects:** reads the system clock and 10 bytes from the
  cryptographic random generator.

  **Complexity:** O(1) time and memory.

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** identifies each published event.

  **Example:**

      iex> Carry.Uuid.v7?(Carry.Uuid.generate())
      true

  **See Also:** `from_parts/2`.
  """
  @spec generate() :: String.t()
  def generate do
    from_parts(System.system_time(:millisecond), :crypto.strong_rand_bytes(10))
  end

  @doc """
  Builds a UUIDv7 from a timestamp and 10 random bytes.

  **Description:** the layout is 48 bits of time, the version `7`, 12
  random bits, the variant `10` and 62 random bits; the top bits of the
  random bytes that the version and variant replace are dropped.

  **Parameters:**
  - `millis` — non-negative integer below 2^48; Unix time in milliseconds.
  - `random` — binary of exactly 10 bytes.

  **Returns:** `String.t()`; the lowercase canonical form.

  **Errors:** `FunctionClauseError` for a binary of another size.

  **Side Effects:** none.

  **Complexity:** O(1) time and memory.

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** keeps the bit layout testable without a
  clock.

  **Example:**

      iex> Carry.Uuid.from_parts(0x018F3C2E7B1A, <<0::80>>)
      "018f3c2e-7b1a-7000-8000-000000000000"

  **See Also:** `generate/0`.
  """
  @spec from_parts(non_neg_integer(), <<_::80>>) :: String.t()
  def from_parts(millis, <<rand_a::12, _::4, rand_b::62, _::2>>) do
    <<a::32, b::16, c::16, d::16, e::48>> =
      <<millis::48, 7::4, rand_a::12, 2::2, rand_b::62>>

    [hex(a, 8), hex(b, 4), hex(c, 4), hex(d, 4), hex(e, 12)] |> Enum.join("-")
  end

  @doc """
  Tells whether a value is a lowercase UUIDv7.

  **Parameters:**
  - `value` — any term.

  **Returns:** `boolean()`; `true` for a string matching the envelope
  pattern `uuidV7`.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(1) time and memory (fixed length).

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** a malformed `task_id` answers
  `INVALID_ARGUMENT`.

  **Example:**

      iex> Carry.Uuid.v7?("018f3c2e-7b1a-7c3d-9f00-0000000000aa")
      true
      iex> Carry.Uuid.v7?("018F3C2E-7B1A-7C3D-9F00-0000000000AA")
      false
      iex> Carry.Uuid.v7?(nil)
      false

  **See Also:** `Carry.Core.validate/3`.
  """
  @spec v7?(term()) :: boolean()
  def v7?(value) when is_binary(value), do: Regex.match?(@v7_pattern, value)
  def v7?(_value), do: false

  # Renders an integer as lowercase hexadecimal, left-padded with zeros.
  #
  # Parameters:
  #   - value: non-negative integer.
  #   - width: positive integer; the number of hexadecimal digits.
  #
  # Returns: String.t(); exactly `width` digits when the value fits.
  #
  # Errors: none. Side Effects: none. Complexity: O(width).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: hex(26, 4) returns "001a".
  defp hex(value, width) do
    value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")
  end
end
