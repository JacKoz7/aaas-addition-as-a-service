# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Application
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Start-up and shutdown of the carry service: configuration,
#                  logging, the Mnesia database and its migrations, the
#                  Kafka client and the supervision tree (metrics,
#                  retention, HTTP on 8080, gRPC on 9090).
# Related Docs:    services/carry/README.md, CLAUDE.md 3 (platform at
#                  start-up) and 6.1, ADR-0032

defmodule Carry.Application do
  @moduledoc """
  The OTP application of the carry service.

  **Description:** `start/2` reads the configuration, installs the JSON
  logger, opens Mnesia and applies the migrations, then starts the
  supervision tree, one-for-one: `Carry.Metrics`, the retention job, the
  HTTP listener and the gRPC server; the brod client runs under the brod
  application's supervisor (`Carry.Publisher.start/1`). Any failure stops
  the start, and the release exits with status 1. On SIGTERM the BEAM
  stops the application: `prep_stop/1` suspends the gRPC listener and
  waits up to 5 s for the calls in progress, then the supervisor stops the
  children and Mnesia is stopped cleanly (exit status 0).

  **Business Justification:** a service that cannot reach a sane state
  must not register itself as healthy (`CLAUDE.md` 3 and 6.1).

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Config`, `Carry.Store`, `Carry.Drain`.
  """

  use Application

  require Logger

  alias Carry.Grpc.Endpoint

  # The :persistent_term key of the configuration.
  @config_key {__MODULE__, :config}

  # Milliseconds the calls in progress get at shutdown (CLAUDE.md 6.1
  # allows 10 s in total).
  @drain_timeout 5_000

  @doc """
  Starts the service (callback of `Application`).

  **Parameters:**
  - `type` — the start type (ignored).
  - `args` — ignored.

  **Returns:** `{:ok, pid}` of the top supervisor, or `{:error, reason}`.

  **Errors:** `{:error, message}` for an invalid configuration or a
  database that cannot be opened; `{:error, reason}` when a child (for
  example a listener on a port in use) does not start.

  **Side Effects:** configures `:logger`; starts Mnesia and the `:httpc`
  profile; opens ports 8080 and 9090; logs `carry started`.

  **Complexity:** O(m) for m migrations.

  **Thread Safety:** called once by the application controller.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see the module documentation.

  **Example:** started by the release (`bin/carry start`).

  **See Also:** `prep_stop/1`.
  """
  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    env = System.get_env()
    Carry.Log.install(Map.get(env, "AAAS_SERVICE", "carry"), :info)

    with {:ok, config} <- Carry.Config.load(env),
         :ok <- :persistent_term.put(@config_key, config),
         :ok <- Carry.Log.install(config.service, config.log_level),
         :ok <- Carry.Drain.init(),
         :ok <- Carry.Digits.start(),
         {:ok, applied} <- Carry.Store.open(config.db_dir, config.migrations_dir),
         :ok <- Carry.Publisher.start(config.kafka_brokers),
         {:ok, pid} <-
           Supervisor.start_link(children(config), strategy: :one_for_one, name: Carry.Supervisor) do
      Logger.info("carry started",
        fields: [
          version: config.version,
          httpPort: config.http_port,
          grpcPort: config.grpc_port,
          migrationsApplied: applied
        ]
      )

      {:ok, pid}
    else
      {:error, reason} ->
        detail = if is_binary(reason), do: reason, else: inspect(reason)
        Logger.error("carry did not start", fields: [detail: detail])
        {:error, detail}
    end
  end

  @doc """
  Drains the gRPC calls before the children stop (callback of
  `Application`).

  **Parameters:**
  - `state` — the application state (unused, returned unchanged).

  **Returns:** `state`.

  **Errors:** none.

  **Side Effects:** suspends the gRPC listener; waits up to 5 s; logs
  `shutting down` with the number of calls in progress.

  **Complexity:** O(waiting).

  **Thread Safety:** called once by the application controller.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the graceful shutdown of `CLAUDE.md` 6.1.

  **Example:** called on SIGTERM.

  **See Also:** `Carry.Drain.stop/2`.
  """
  @impl true
  @spec prep_stop(term()) :: term()
  def prep_stop(state) do
    Logger.info("shutting down", fields: [inProgress: Carry.Drain.in_progress()])
    result = Carry.Drain.stop(Endpoint.listener(), @drain_timeout)
    Logger.info("gRPC calls drained", fields: [result: Atom.to_string(result)])
    state
  end

  @doc """
  Logs the end of the shutdown (callback of `Application`).

  **Parameters:**
  - `state` — ignored.

  **Returns:** `:ok`.

  **Errors:** none.

  **Side Effects:** logs `stopped`.

  **Complexity:** O(1).

  **Thread Safety:** called once by the application controller.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the operator sees that the stop completed.

  **Example:** called on SIGTERM after the supervisor stopped.

  **See Also:** `prep_stop/1`.
  """
  @impl true
  @spec stop(term()) :: :ok
  def stop(_state) do
    Logger.info("stopped")
    :ok
  end

  @doc """
  The configuration of the running service.

  **Parameters:** none.

  **Returns:** `t:Carry.Config.t/0`.

  **Errors:** `ArgumentError` before `start/2` stored it.

  **Side Effects:** none.

  **Complexity:** O(1) (`:persistent_term`).

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** request handlers read the digit URL
  template without a process round trip.

  **Example:** `Carry.Application.config().grpc_port` is 9090 by default.

  **See Also:** `Carry.Config.load/1`.
  """
  @spec config() :: Carry.Config.t()
  def config, do: :persistent_term.get(@config_key)

  # The children of the top supervisor.
  #
  # Parameters:
  #   - config: Carry.Config.t().
  #
  # Returns: [Supervisor.child_spec()], in start order.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: children(config) has four children.
  defp children(config) do
    [
      {Carry.Metrics, config.version},
      {Carry.Retention, config.retention_hours},
      Carry.Http.child_spec(config.http_port),
      {GRPC.Server.Supervisor,
       endpoint: Endpoint,
       port: config.grpc_port,
       start_server: true,
       max_body_size: 4_096,
       exception_log_filter: {Carry.Grpc.Server, :log_exception?},
       adapter_opts: [max_connections: 256]}
    ]
  end
end
