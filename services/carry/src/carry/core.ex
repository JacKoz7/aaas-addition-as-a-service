# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Core
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         The carry arithmetic without I/O: validation of a
#                  Propagate request and the propagation of a carry through
#                  the digits, with the digit services behind a function.
# Related Docs:    contracts/proto/aaas/carry/v1/carry.proto, CLAUDE.md 1
#                  (rule 5) and 3 (step 7), ADR-0032

defmodule Carry.Core do
  @moduledoc """
  Validation and propagation of a carry.

  **Description:** a number is a list of decimal digits, least significant
  first. Propagating a carry at `position` replaces that digit with its
  successor, as reported by the digit service of the digit; while the
  digit service reports a carry (only `digit-9` does), the next position
  is visited. A carry past the highest digit creates a new digit: the
  successor of 0, asked from `digit-0`. The module never adds natively
  (`CLAUDE.md` 1, rule 5): only the position index and the call counter
  are incremented natively, as helper code.

  **Business Justification:** `9 + 1 = 10`, `99 + 1 = 100` and
  `99 999 + 1 = 100 000` are possible only because a carry reaches the
  higher digits.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Digits`, `Carry.Propagation`,
  `contracts/proto/aaas/carry/v1/carry.proto`.
  """

  alias Carry.Uuid

  # The most digits of a request: the largest argument of the successor,
  # 199 997, has six (contracts/proto/aaas/carry/v1/carry.proto).
  @max_digits 6

  @typedoc "Decimal digits, least significant first."
  @type digits :: [0..9]

  @typedoc """
  The successor of one digit as reported by its digit service:
  `{:ok, {next, carry}}`, or `{:error, reason}`.
  """
  @type next_digit :: (0..9 -> {:ok, {0..9, boolean()}} | {:error, term()})

  @doc """
  Validates the fields of a `PropagateRequest`.

  **Description:** `digits` must have 1 to 6 elements in `0..9`,
  `position` must be in `0..length(digits)` and `task_id` must be a
  lowercase UUIDv7. The task identifier is checked first.

  **Parameters:**
  - `digits` — list of non-negative integers (the decoded `uint32` field).
  - `position` — non-negative integer.
  - `task_id` — `String.t()`.

  **Returns:** `:ok`, or `{:error, message}` with the first rule broken,
  answered as `INVALID_ARGUMENT`.

  **Errors:** none (invalid input is a return value).

  **Side Effects:** none.

  **Complexity:** O(d) time and O(1) memory for d digits.

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** a malformed request must be refused before
  any digit service is asked or anything is recorded.

  **Example:**

      iex> Carry.Core.validate([0, 9], 1, "018f3c2e-7b1a-7c3d-9f00-0000000000aa")
      :ok
      iex> Carry.Core.validate([0, 9], 3, "018f3c2e-7b1a-7c3d-9f00-0000000000aa")
      {:error, "position must be in 0..2"}
      iex> Carry.Core.validate([10], 0, "018f3c2e-7b1a-7c3d-9f00-0000000000aa")
      {:error, "every digit must be in 0..9"}
      iex> Carry.Core.validate([0], 0, "")
      {:error, "task_id must be a lowercase UUIDv7"}

  **See Also:** `propagate/3`.
  """
  @spec validate([non_neg_integer()], non_neg_integer(), String.t()) :: :ok | {:error, String.t()}
  def validate(digits, position, task_id) do
    count = length(digits)

    cond do
      not Uuid.v7?(task_id) -> {:error, "task_id must be a lowercase UUIDv7"}
      count == 0 or count > @max_digits -> {:error, "digits must have 1 to #{@max_digits} elements"}
      Enum.any?(digits, &(&1 > 9)) -> {:error, "every digit must be in 0..9"}
      position > count -> {:error, "position must be in 0..#{count}"}
      true -> :ok
    end
  end

  @doc """
  Propagates a carry at `position` through the digits.

  **Description:** asks `next_digit` for the successor of the digit at
  `position`, stores it, and continues at the next position while the
  answer carries. At the position after the highest digit, the successor
  of 0 is appended; it must not carry. The input must have passed
  `validate/3`.

  **Parameters:**
  - `digits` — `t:digits/0`; the number before the carry.
  - `position` — integer in `0..length(digits)`; the digit receiving the
    carry.
  - `next_digit` — `t:next_digit/0`; asks the digit service of one digit.

  **Returns:** `{:ok, result, calls}` with the digits after the carry and
  the number of digit service calls (1 to 7), or `{:error, reason}`.

  **Errors:** `{:error, reason}` from `next_digit`, unchanged;
  `{:error, :new_digit_carries}` when the successor of 0 reports a carry.

  **Side Effects:** those of `next_digit` (one call per visited
  position).

  **Complexity:** O(d^2) time (list updates) and O(d) memory for d
  digits, d at most 7.

  **Thread Safety:** pure apart from `next_digit`.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the core of `CarryService.Propagate`: 99 + 1
  becomes 100 by asking the digit services, never by native addition.

  **Example:**

      iex> successors = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
      iex> next = fn d -> {:ok, {Enum.at(successors, d), d == 9}} end
      iex> Carry.Core.propagate([0, 9, 9], 1, next)
      {:ok, [0, 0, 0, 1], 3}
      iex> Carry.Core.propagate([0, 1], 1, next)
      {:ok, [0, 2], 1}
      iex> Carry.Core.propagate([0, 1], 1, fn _ -> {:error, :unavailable} end)
      {:error, :unavailable}

  **See Also:** `validate/3`, `Carry.Digits.next/2`.
  """
  @spec propagate(digits(), non_neg_integer(), next_digit()) ::
          {:ok, digits(), pos_integer()} | {:error, term()}
  def propagate(digits, position, next_digit), do: step(digits, position, next_digit, 1)

  # One position of the propagation.
  #
  # Description: past the highest digit, appends the successor of 0;
  # otherwise replaces the digit and continues while it carries.
  #
  # Parameters:
  #   - digits: digits(); the number so far.
  #   - position: non-negative integer; the position to visit.
  #   - next_digit: next_digit(); asks a digit service.
  #   - calls: positive integer; the number of this digit service call.
  #
  # Returns: {:ok, result, calls} or {:error, reason} (see propagate/3).
  #
  # Errors: see propagate/3. Side Effects: calls next_digit.
  # Complexity: O(d) per position. Thread Safety: pure apart from
  # next_digit. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: step([9], 0, next, 1) asks for 9, then for 0, and returns
  # {:ok, [0, 1], 2}.
  defp step(digits, position, next_digit, calls) when position == length(digits) do
    case next_digit.(0) do
      {:ok, {next, false}} -> {:ok, digits ++ [next], calls}
      {:ok, {_next, true}} -> {:error, :new_digit_carries}
      {:error, reason} -> {:error, reason}
    end
  end

  defp step(digits, position, next_digit, calls) do
    case next_digit.(Enum.at(digits, position)) do
      {:ok, {next, true}} ->
        step(List.replace_at(digits, position, next), position + 1, next_digit, calls + 1)

      {:ok, {next, false}} ->
        {:ok, List.replace_at(digits, position, next), calls}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
