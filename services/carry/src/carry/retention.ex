# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Retention
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         The retention job of the propagation log: every hour,
#                  deletes the records older than AAAS_RETENTION_HOURS.
# Related Docs:    services/carry/docs/CAPACITY.md,
#                  services/carry/docs/DATA_CLASSIFICATION.md, CLAUDE.md 6.6

defmodule Carry.Retention do
  @moduledoc """
  Deletes old records of the propagation log.

  **Description:** a process that runs `Carry.Store.prune/1` one minute
  after start-up and then every hour, with the cut-off
  `now - AAAS_RETENTION_HOURS`. The records are needed only while their
  addition can still be retried (minutes; 35 minutes for the largest
  addition), so the default of 24 hours keeps a wide margin. A failed run
  is logged and retried at the next interval.

  **Business Justification:** the log grows with every carry (about one
  record per ten successor calls); unbounded data must have a retention
  (`CLAUDE.md` 6.6).

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Store.prune/1`, `docs/CAPACITY.md`.
  """

  use GenServer

  require Logger

  # Milliseconds from the start to the first run.
  @first_run 60_000

  # Milliseconds between two runs.
  @interval 3_600_000

  @doc """
  Starts the retention process.

  **Parameters:**
  - `hours` — integer in `1..8760`; `AAAS_RETENTION_HOURS`.

  **Returns:** `GenServer.on_start()`.

  **Errors:** `{:error, {:already_started, pid}}` for a second instance.

  **Side Effects:** schedules the first run.

  **Complexity:** O(1).

  **Thread Safety:** one instance per node.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see the module documentation.

  **Example:** `{Carry.Retention, 24}` as a child of the supervisor.

  **See Also:** `handle_info/2`.
  """
  @spec start_link(pos_integer()) :: GenServer.on_start()
  def start_link(hours), do: GenServer.start_link(__MODULE__, hours, name: __MODULE__)

  @doc """
  Schedules the first run (GenServer callback).

  **Parameters:**
  - `hours` — positive integer; the retention.

  **Returns:** `{:ok, hours}`.

  **Errors:** none.

  **Side Effects:** a timer message in one minute.

  **Complexity:** O(1).

  **Thread Safety:** runs in the retention process.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see `start_link/1`.

  **Example:** called by `GenServer.start_link/3`.

  **See Also:** `handle_info/2`.
  """
  @impl true
  @spec init(pos_integer()) :: {:ok, pos_integer()}
  def init(hours) do
    Process.send_after(self(), :prune, @first_run)
    {:ok, hours}
  end

  @doc """
  Runs one pruning and schedules the next (GenServer callback).

  **Parameters:**
  - `message` — `:prune`.
  - `hours` — positive integer; the retention.

  **Returns:** `{:noreply, hours}`.

  **Errors:** none: a failure is logged.

  **Side Effects:** deletes Mnesia records; counts
  `carry_retention_deleted_total`; logs the number deleted (info) or the
  failure (warning).

  **Complexity:** O(n) for n records.

  **Thread Safety:** runs in the retention process.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see the module documentation.

  **Example:** `send(Carry.Retention, :prune)` runs it at once.

  **See Also:** `Carry.Store.prune/1`.
  """
  @impl true
  @spec handle_info(:prune, pos_integer()) :: {:noreply, pos_integer()}
  def handle_info(:prune, hours) do
    cutoff = System.system_time(:millisecond) - hours * 3_600_000

    case Carry.Store.prune(cutoff) do
      {:ok, 0} ->
        :ok

      {:ok, deleted} ->
        for _ <- 1..deleted, do: Carry.Metrics.count("carry_retention_deleted_total")
        Logger.info("propagation log pruned", fields: [deleted: deleted, retentionHours: hours])

      {:error, reason} ->
        Logger.warning("propagation log not pruned", fields: [detail: inspect(reason)])
    end

    Process.send_after(self(), :prune, @interval)
    {:noreply, hours}
  end
end
