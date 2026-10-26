# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Metrics
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         The Prometheus metrics of the service: counters and one
#                  histogram in a public ETS table, rendered in the text
#                  exposition format for GET /metrics.
# Related Docs:    services/carry/docs/API.md, services/carry/docs/SLO.md,
#                  services/carry/docs/RUNBOOK.md

defmodule Carry.Metrics do
  @moduledoc """
  Prometheus metrics of the carry service.

  **Description:** the metrics are

  - `carry_build_info{version}` — always 1;
  - `carry_propagations_total{outcome}` — `Propagate` calls by outcome:
    `ok` (computed), `replayed` (answered from the Mnesia log),
    `invalid_argument`, `unavailable`, `internal`;
  - `carry_propagation_duration_seconds` — histogram of the time to serve
    one call;
  - `carry_digit_calls_total{digit, outcome}` — calls to the digit
    services, `ok` or `error` per attempt;
  - `carry_dependency_failures_total{dependency}` — a dependency (`digit-N`,
    `database`, `broker`) failed after its retries;
  - `carry_retention_deleted_total` — propagation records removed by the
    retention job.

  Counters live in a public ETS table with write concurrency, owned by a
  process of the supervision tree, so any process updates them without a
  message round trip. The text output is sorted, so it is stable.

  **Business Justification:** the SLO of the service is measured from
  these series (`docs/SLO.md`), and the runbook's diagnosis starts from
  them.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Http`, `docs/SLO.md`.
  """

  use GenServer

  # The ETS table of the metrics.
  @table :carry_metrics

  # Upper bounds, in seconds, of the duration histogram (as in successor).
  @buckets [0.001, 0.0025, 0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1, 2]

  # The help text and type of every metric family, in output order.
  @families [
    {"carry_build_info", "gauge", "Version of the running carry service."},
    {"carry_propagations_total", "counter", "Propagate calls by outcome."},
    {"carry_propagation_duration_seconds", "histogram", "Time to serve a Propagate call."},
    {"carry_digit_calls_total", "counter", "Calls to the digit services by digit and outcome."},
    {"carry_dependency_failures_total", "counter", "Failed calls to a dependency after retries."},
    {"carry_retention_deleted_total", "counter",
     "Propagation records removed by the retention job."}
  ]

  @doc """
  Starts the owner of the metrics table.

  **Parameters:**
  - `version` — `String.t()`; the label of `carry_build_info`.

  **Returns:** `GenServer.on_start()`.

  **Errors:** `{:error, reason}` when the table already exists.

  **Side Effects:** creates the named ETS table `:carry_metrics`.

  **Complexity:** O(1).

  **Thread Safety:** start once per node.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the table must outlive every request.

  **Example:** `{Carry.Metrics, "0.1.0"}` as a child of the supervisor.

  **See Also:** `render/0`.
  """
  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(version), do: GenServer.start_link(__MODULE__, version, name: __MODULE__)

  @doc """
  Creates the table and sets `carry_build_info` (GenServer callback).

  **Parameters:**
  - `version` — `String.t()`.

  **Returns:** `{:ok, nil}`.

  **Errors:** `ArgumentError` when the table name is taken.

  **Side Effects:** creates the ETS table.

  **Complexity:** O(1).

  **Thread Safety:** runs in the owner process.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see `start_link/1`.

  **Example:** called by `GenServer.start_link/3`.

  **See Also:** `start_link/1`.
  """
  @impl true
  @spec init(String.t()) :: {:ok, nil}
  def init(version) do
    :ets.new(@table, [:named_table, :public, write_concurrency: true])
    :ets.insert(@table, {{"carry_build_info", [version: version]}, 1})
    {:ok, nil}
  end

  @doc """
  Adds one to a counter series.

  **Parameters:**
  - `name` — `String.t()`; a counter family of the module documentation.
  - `labels` — keyword list of label names and values.

  **Returns:** `:ok`.

  **Errors:** `ArgumentError` when the table does not exist.

  **Side Effects:** updates the ETS table.

  **Complexity:** O(1).

  **Thread Safety:** safe for concurrent use (atomic ETS update).

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** counts calls, outcomes and failures.

  **Example:** `Carry.Metrics.count("carry_propagations_total", outcome: "ok")`.

  **See Also:** `observe/1`.
  """
  @spec count(String.t(), keyword()) :: :ok
  def count(name, labels \\ []) do
    bump({name, labels}, 1)
  end

  @doc """
  Records one duration in `carry_propagation_duration_seconds`.

  **Parameters:**
  - `microseconds` — non-negative integer; the duration.

  **Returns:** `:ok`.

  **Errors:** `ArgumentError` when the table does not exist.

  **Side Effects:** updates the ETS table (the bucket counters, the count
  and the sum in microseconds).

  **Complexity:** O(b) for b buckets.

  **Thread Safety:** safe for concurrent use; a scrape may see the count
  and the sum of one observation updated a moment apart.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the latency SLO (`docs/SLO.md`).

  **Example:** `Carry.Metrics.observe(1_250)` records 1.25 ms.

  **See Also:** `count/2`.
  """
  @spec observe(non_neg_integer()) :: :ok
  def observe(microseconds) do
    name = "carry_propagation_duration_seconds"

    for bound <- @buckets, microseconds <= bound * 1_000_000 do
      bump({name <> "_bucket", [le: bound]}, 1)
    end

    bump({name <> "_count", []}, 1)
    bump({name <> "_sum", []}, microseconds)
    :ok
  end

  @doc """
  Renders every metric in the Prometheus text format.

  **Parameters:** none.

  **Returns:** `iodata()`; `# HELP` and `# TYPE` lines per family, then
  its series, sorted.

  **Errors:** `ArgumentError` when the table does not exist.

  **Side Effects:** reads the ETS table.

  **Complexity:** O(s log s) for s series.

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the body of `GET /metrics`.

  **Example:** `Carry.Metrics.render()` contains
  `carry_build_info{version="0.1.0"} 1`.

  **See Also:** `Carry.Http`.
  """
  @spec render() :: iodata()
  def render do
    series = :ets.tab2list(@table)

    for {family, type, help} <- @families do
      lines =
        series
        |> Enum.filter(fn {{name, _labels}, _value} -> family?(name, family) end)
        |> Enum.map(&series_line/1)
        |> Enum.sort()

      [
        "# HELP #{family} #{help}\n",
        "# TYPE #{family} #{type}\n" | lines ++ histogram_tail(family, type, series)
      ]
    end
  end

  # Adds to one series, creating it at 0 first.
  #
  # Parameters:
  #   - key: {name, labels}; the series.
  #   - increment: non-negative integer.
  #
  # Returns: :ok.
  #
  # Errors: ArgumentError when the table does not exist.
  # Side Effects: updates the ETS table. Complexity: O(1).
  # Thread Safety: safe (atomic ETS update).
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: bump({"x", []}, 1) makes the series x count one more.
  defp bump(key, increment) do
    :ets.update_counter(@table, key, increment, {key, 0})
    :ok
  end

  # Whether a series name belongs to a family (histograms have suffixes).
  #
  # Parameters:
  #   - name: String.t(); the series name.
  #   - family: String.t(); the family name.
  #
  # Returns: boolean.
  #
  # Errors: none. Side Effects: none. Complexity: O(n).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: family?("x_bucket", "x") is true.
  defp family?(name, family),
    do: name == family or name in for(s <- ["_bucket", "_count", "_sum"], do: family <> s)

  # The final +Inf bucket of a histogram, equal to its count; nothing for
  # the other types.
  #
  # Parameters:
  #   - family: String.t(); the family name.
  #   - type: String.t(); its type.
  #   - series: list of ETS rows.
  #
  # Returns: iodata.
  #
  # Errors: none. Side Effects: none. Complexity: O(s).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: before any observation, ~s(x_bucket{le="+Inf"} 0).
  defp histogram_tail(family, "histogram", series) do
    count =
      Enum.find_value(series, 0, fn {{name, _}, value} -> name == family <> "_count" && value end)

    ["#{family}_bucket{le=\"+Inf\"} #{count}\n"]
  end

  defp histogram_tail(_family, _type, _series), do: []

  # One line of the text format.
  #
  # Description: the histogram sum is stored in microseconds and printed
  # in seconds.
  #
  # Parameters:
  #   - row: {{name, labels}, value}; an ETS row.
  #
  # Returns: String.t(); `name{label="value",...} value` and a newline.
  #
  # Errors: none. Side Effects: none. Complexity: O(n).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: series_line({{"x", [a: "b"]}, 2}) returns ~s(x{a="b"} 2\n).
  defp series_line({{name, labels}, value}) do
    value = if String.ends_with?(name, "_sum"), do: value / 1_000_000, else: value
    labels = Enum.map_join(labels, ",", fn {key, label} -> ~s(#{key}="#{label}") end)
    if labels == "", do: "#{name} #{value}\n", else: "#{name}{#{labels}} #{value}\n"
  end
end
