# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Digits
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         HTTP client of the ten digit services: GET /next of
#                  digit-N with a per-attempt timeout, three attempts with
#                  jitter and a check of the answer against the contract.
# Related Docs:    contracts/http/digit.yaml, CLAUDE.md 4.4 and 6.1
#                  (timeouts and retries), ADR-0021, ADR-0032

defmodule Carry.Digits do
  @moduledoc """
  Asks a digit service for the successor of its digit.

  **Description:** `next/3` sends `GET /next` to the digit service of the
  digit, at the URL of `AAAS_DIGIT_URL_TEMPLATE` with `{digit}` replaced,
  through the `:httpc` profile `:carry_digits` (persistent connections,
  kept for 5 s, shorter than the 10 s idle timeout of the digit services).
  An attempt has at most 250 ms and never outlives the request deadline;
  a transport error, a timeout or a 5xx answer is retried twice, after
  about 50 ms and 100 ms with up to 25 ms of jitter. The answer must be
  the contract's `{"digit": d, "next": n, "carry": c}` for the digit that
  was asked; any other answer is not retried.

  **Business Justification:** the carry service never computes a digit
  itself (`CLAUDE.md` 1, rule 5): every successor of a digit comes from
  the service that owns that digit.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Core.propagate/3`, `contracts/http/digit.yaml`.
  """

  require Logger

  # The :httpc profile of the digit services.
  @profile :carry_digits

  # Milliseconds one attempt may take at most.
  @attempt_timeout 250

  # Pauses before the second and the third attempt, in milliseconds.
  @backoff [50, 100]

  @doc """
  Starts the `:httpc` profile of the digit services.

  **Parameters:** none.

  **Returns:** `:ok`.

  **Errors:** `MatchError` when `:inets` is not running.

  **Side Effects:** starts the `:carry_digits` profile under the `:inets`
  supervisor (idempotent).

  **Complexity:** O(1).

  **Thread Safety:** call once at start-up.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** persistent connections keep a digit call
  below a millisecond.

  **Example:** `Carry.Digits.start()` in `Carry.Application.start/2`.

  **See Also:** `next/3`.
  """
  @spec start() :: :ok
  def start do
    case :inets.start(:httpc, profile: @profile) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok =
      :httpc.set_options(
        [max_sessions: 4, max_keep_alive_length: 1_000, keep_alive_timeout: 5_000],
        @profile
      )
  end

  @doc """
  Asks the digit service of `digit` for its successor.

  **Parameters:**
  - `template` — `String.t()`; `AAAS_DIGIT_URL_TEMPLATE`, with `{digit}`.
  - `digit` — integer in `0..9`.
  - `options` — keyword list: `:deadline` (monotonic milliseconds by
    which the call must end, required) and `:traceparent` (sent as the
    header when given).

  **Returns:** `{:ok, {next, carry}}` with `next` in `0..9` and `carry` a
  boolean; `{:error, {:unavailable, detail}}` when no attempt succeeded;
  `{:error, {:invalid_answer, detail}}` when the service answered outside
  the contract.

  **Errors:** none (failures are return values).

  **Side Effects:** 1 to 3 HTTP requests; counts
  `carry_digit_calls_total` per attempt and
  `carry_dependency_failures_total{dependency="digit-N"}` on failure; logs
  a warning on failure.

  **Complexity:** O(1) time and memory (bounded body).

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** one step of a carry: the successor of one
  digit.

  **Example:** with digit-9 running,
  `Carry.Digits.next("http://digit-{digit}:8080", 9, deadline: deadline)`
  returns `{:ok, {0, true}}`.

  **See Also:** `parse/2`.
  """
  @spec next(String.t(), 0..9, keyword()) ::
          {:ok, {0..9, boolean()}} | {:error, {:unavailable | :invalid_answer, String.t()}}
  def next(template, digit, options) do
    url = String.replace(template, "{digit}", Integer.to_string(digit)) <> "/next"

    headers =
      case Keyword.get(options, :traceparent) do
        nil -> [{~c"accept", ~c"application/json"}]
        trace -> [{~c"accept", ~c"application/json"}, {~c"traceparent", String.to_charlist(trace)}]
      end

    attempt(
      String.to_charlist(url),
      headers,
      digit,
      Keyword.fetch!(options, :deadline),
      [0 | @backoff],
      nil
    )
  end

  @doc """
  Checks the body of a `GET /next` answer of the digit service of `digit`.

  **Parameters:**
  - `body` — binary; the response body.
  - `digit` — integer in `0..9`; the digit that was asked.

  **Returns:** `{:ok, {next, carry}}`, or `{:error, {:invalid_answer,
  detail}}`.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(n) in the body.

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** an answer for the wrong digit, or outside
  0..9, would corrupt the sum; it is refused instead.

  **Example:**

      iex> Carry.Digits.parse(~s({"digit":9,"next":0,"carry":true}), 9)
      {:ok, {0, true}}
      iex> Carry.Digits.parse(~s({"digit":8,"next":9,"carry":false}), 9)
      {:error, {:invalid_answer, "digit-9 answered for digit 8"}}

  **See Also:** `next/3`.
  """
  @spec parse(binary(), 0..9) :: {:ok, {0..9, boolean()}} | {:error, {:invalid_answer, String.t()}}
  def parse(body, digit) do
    case JSON.decode(body) do
      {:ok, %{"digit" => ^digit, "next" => next, "carry" => carry}}
      when next in 0..9 and is_boolean(carry) ->
        {:ok, {next, carry}}

      {:ok, %{"digit" => other}} when other != digit ->
        {:error, {:invalid_answer, "digit-#{digit} answered for digit #{inspect(other)}"}}

      _ ->
        {:error, {:invalid_answer, "digit-#{digit} answered outside the contract"}}
    end
  end

  # Makes the remaining attempts of one call.
  #
  # Description: each element of `pauses` is one attempt, preceded by a
  # pause of that many milliseconds plus up to 25 ms of jitter. Stops when
  # the deadline leaves no time for an attempt.
  #
  # Parameters:
  #   - url: charlist; the URL of GET /next.
  #   - headers: list of {charlist, charlist}; request headers.
  #   - digit: 0..9; the digit asked.
  #   - deadline: integer; monotonic milliseconds.
  #   - pauses: list of non-negative integers; one per remaining attempt.
  #   - last: String.t() or nil; the failure of the previous attempt.
  #
  # Returns: see next/3.
  #
  # Errors: none. Side Effects: HTTP requests, metrics, a warning log
  # line on failure. Complexity: O(attempts).
  # Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: attempt(url, headers, 9, deadline, [0, 50, 100], nil) makes
  # up to three attempts.
  defp attempt(_url, _headers, digit, _deadline, [], last), do: unavailable(digit, last)

  defp attempt(url, headers, digit, deadline, [pause | pauses], last) do
    if pause > 0, do: Process.sleep(pause + :rand.uniform(26) - 1)
    timeout = min(@attempt_timeout, deadline - System.monotonic_time(:millisecond))

    if timeout <= 0 do
      unavailable(digit, last || "request deadline exceeded")
    else
      case request(url, headers, timeout) do
        {:ok, 200, body} ->
          outcome(digit, "ok")
          parse(body, digit)

        {:ok, status, _body} when status >= 500 ->
          outcome(digit, "error")
          attempt(url, headers, digit, deadline, pauses, "HTTP #{status}")

        {:ok, status, _body} ->
          outcome(digit, "error")
          {:error, {:invalid_answer, "digit-#{digit} answered HTTP #{status}"}}

        {:error, reason} ->
          outcome(digit, "error")
          attempt(url, headers, digit, deadline, pauses, inspect(reason))
      end
    end
  end

  # One HTTP GET through the profile.
  #
  # Parameters:
  #   - url: charlist.
  #   - headers: list of {charlist, charlist}.
  #   - timeout: positive integer; milliseconds for the whole request.
  #
  # Returns: {:ok, status, body} or {:error, reason}.
  #
  # Errors: none. Side Effects: one HTTP request. Complexity: O(n) in the
  # body. Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: request(~c"http://digit-9:8080/next", [], 250) returns
  # {:ok, 200, body}.
  defp request(url, headers, timeout) do
    options = [timeout: timeout, connect_timeout: timeout, autoredirect: false]

    case :httpc.request(:get, {url, headers}, options, [body_format: :binary], @profile) do
      {:ok, {{_version, status, _reason}, _headers, body}} -> {:ok, status, body}
      {:error, reason} -> {:error, reason}
    end
  end

  # Counts one attempt in carry_digit_calls_total.
  #
  # Parameters:
  #   - digit: 0..9.
  #   - result: "ok" or "error".
  #
  # Returns: :ok.
  #
  # Errors: none. Side Effects: updates a metric. Complexity: O(1).
  # Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: outcome(9, "ok").
  defp outcome(digit, result) do
    Carry.Metrics.count("carry_digit_calls_total", digit: digit, outcome: result)
  end

  # The failure of a call whose attempts are exhausted.
  #
  # Parameters:
  #   - digit: 0..9.
  #   - detail: String.t() or nil; the last failure.
  #
  # Returns: {:error, {:unavailable, detail}}.
  #
  # Errors: none. Side Effects: counts carry_dependency_failures_total and
  # logs a warning. Complexity: O(1). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: unavailable(9, "timeout") logs "digit service unavailable".
  defp unavailable(digit, detail) do
    detail = "digit-#{digit}: #{detail || "no attempt left"}"
    Carry.Metrics.count("carry_dependency_failures_total", dependency: "digit-#{digit}")
    Logger.warning("digit service unavailable", fields: [detail: detail])
    {:error, {:unavailable, detail}}
  end
end
