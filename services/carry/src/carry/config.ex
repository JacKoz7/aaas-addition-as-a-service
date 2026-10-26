# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Config
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         The configuration of the service, read from environment
#                  variables (AAAS_BOOTSTRAP=env) and checked at start-up.
# Related Docs:    services/carry/README.md (Configuration), CLAUDE.md 3
#                  (platform at start-up) and 6.1

defmodule Carry.Config do
  @moduledoc """
  The configuration of the carry service.

  **Description:** `load/1` reads the variables of the README's
  configuration table from a map of environment variables, applies the
  defaults and refuses invalid values. Until P5.2 only
  `AAAS_BOOTSTRAP=env` is supported; `platform` (config-server, OpenBao,
  Consul) stops the start.

  Fields of `t:t/0`: `service`, `env`, `version` (strings); `http_port` and
  `grpc_port` (1..65535); `kafka_brokers` (list of `{host, port}` with the
  host as a charlist, for brod); `db_dir` and `migrations_dir` (paths);
  `digit_url_template` (a URL containing `{digit}`); `log_level`
  (`:debug`, `:info`, `:warning` or `:error`); `retention_hours`
  (1..8760).

  **Business Justification:** no host, port or path is hard-coded
  (`CLAUDE.md` 6.1); a wrong value stops the service at start-up instead of
  failing the first addition.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Application`.
  """

  @typedoc "The checked configuration (fields in the module documentation)."
  @type t :: %__MODULE__{
          service: String.t(),
          env: String.t(),
          version: String.t(),
          http_port: 1..65_535,
          grpc_port: 1..65_535,
          kafka_brokers: [{charlist(), 1..65_535}],
          db_dir: String.t(),
          migrations_dir: String.t(),
          digit_url_template: String.t(),
          log_level: :debug | :info | :warning | :error,
          retention_hours: 1..8760
        }

  @enforce_keys [
    :service,
    :env,
    :version,
    :http_port,
    :grpc_port,
    :kafka_brokers,
    :db_dir,
    :migrations_dir,
    :digit_url_template,
    :log_level,
    :retention_hours
  ]
  defstruct @enforce_keys

  # The version of the service, reported in logs and carry_build_info.
  @version Mix.Project.config()[:version]

  @doc """
  Reads and checks the configuration.

  **Parameters:**
  - `env` — map of environment variable names to values, usually
    `System.get_env()`.

  **Returns:** `{:ok, t()}`, or `{:error, message}` naming the first
  invalid variable.

  **Errors:** none (invalid values are a return value).

  **Side Effects:** none.

  **Complexity:** O(n) in the length of the values.

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the start-up check of `CLAUDE.md` 3: a
  service that cannot be configured must not start.

  **Example:**

      iex> {:ok, config} = Carry.Config.load(%{})
      iex> {config.grpc_port, config.kafka_brokers, config.log_level}
      {9090, [{~c"redpanda", 9092}], :info}
      iex> Carry.Config.load(%{"AAAS_BOOTSTRAP" => "platform"})
      {:error, "AAAS_BOOTSTRAP=platform is not supported before P5.2; use env"}
      iex> Carry.Config.load(%{"AAAS_GRPC_PORT" => "0"})
      {:error, "AAAS_GRPC_PORT must be an integer in 1..65535"}

  **See Also:** `Carry.Application.start/2`.
  """
  @spec load(%{optional(String.t()) => String.t()}) :: {:ok, t()} | {:error, String.t()}
  def load(env) do
    get = fn name, default -> Map.get(env, name, default) end

    with :ok <- bootstrap(get.("AAAS_BOOTSTRAP", "env")),
         {:ok, http_port} <- integer("AAAS_HTTP_PORT", get.("AAAS_HTTP_PORT", "8080"), 1..65_535),
         {:ok, grpc_port} <- integer("AAAS_GRPC_PORT", get.("AAAS_GRPC_PORT", "9090"), 1..65_535),
         {:ok, brokers} <- brokers(get.("AAAS_KAFKA_BROKERS", "redpanda:9092")),
         {:ok, template} <-
           digit_url_template(get.("AAAS_DIGIT_URL_TEMPLATE", "http://digit-{digit}:8080")),
         {:ok, level} <- log_level(get.("AAAS_LOG_LEVEL", "info")),
         {:ok, hours} <-
           integer("AAAS_RETENTION_HOURS", get.("AAAS_RETENTION_HOURS", "24"), 1..8760) do
      {:ok,
       %__MODULE__{
         service: get.("AAAS_SERVICE", "carry"),
         env: get.("AAAS_ENV", "local"),
         version: @version,
         http_port: http_port,
         grpc_port: grpc_port,
         kafka_brokers: brokers,
         db_dir: get.("AAAS_DB_DIR", "/data/mnesia"),
         migrations_dir: get.("AAAS_MIGRATIONS_DIR", "/app/migrations"),
         digit_url_template: template,
         log_level: level,
         retention_hours: hours
       }}
    end
  end

  # Checks AAAS_BOOTSTRAP.
  #
  # Parameters:
  #   - mode: String.t(); the value.
  #
  # Returns: :ok for "env", {:error, message} otherwise.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: bootstrap("env") returns :ok.
  defp bootstrap("env"), do: :ok

  defp bootstrap(mode),
    do: {:error, "AAAS_BOOTSTRAP=#{mode} is not supported before P5.2; use env"}

  # Parses a decimal integer within a range.
  #
  # Parameters:
  #   - name: String.t(); the variable, for the message.
  #   - text: String.t(); the value.
  #   - range: Range.t(); the allowed values.
  #
  # Returns: {:ok, integer} or {:error, message}.
  #
  # Errors: none. Side Effects: none. Complexity: O(n) in the text.
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: integer("X", "8080", 1..65_535) returns {:ok, 8080}.
  defp integer(name, text, first..last//_) do
    case Integer.parse(text) do
      {value, ""} when value >= first and value <= last -> {:ok, value}
      _ -> {:error, "#{name} must be an integer in #{first}..#{last}"}
    end
  end

  # Parses AAAS_KAFKA_BROKERS, a comma-separated list of host:port.
  #
  # Parameters:
  #   - text: String.t(); the value.
  #
  # Returns: {:ok, [{charlist, port}]} or {:error, message}.
  #
  # Errors: none. Side Effects: none. Complexity: O(n) in the text.
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: brokers("a:1,b:2") returns {:ok, [{~c"a", 1}, {~c"b", 2}]}.
  defp brokers(text) do
    parsed =
      for broker <- String.split(text, ",", trim: true) do
        with [host, port] when host != "" <- String.split(String.trim(broker), ":"),
             {:ok, port} <- integer("port", port, 1..65_535) do
          {String.to_charlist(host), port}
        else
          _ -> :error
        end
      end

    if parsed == [] or :error in parsed,
      do: {:error, "AAAS_KAFKA_BROKERS must be a comma-separated list of host:port"},
      else: {:ok, parsed}
  end

  # Checks AAAS_DIGIT_URL_TEMPLATE.
  #
  # Parameters:
  #   - template: String.t(); the value.
  #
  # Returns: {:ok, template} when it is an http URL containing {digit},
  # {:error, message} otherwise.
  #
  # Errors: none. Side Effects: none. Complexity: O(n) in the text.
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: digit_url_template("http://digit-{digit}:8080") returns it.
  defp digit_url_template(template) do
    if String.starts_with?(template, "http://") and String.contains?(template, "{digit}"),
      do: {:ok, String.trim_trailing(template, "/")},
      else: {:error, "AAAS_DIGIT_URL_TEMPLATE must be an http:// URL containing {digit}"}
  end

  # Parses AAAS_LOG_LEVEL.
  #
  # Parameters:
  #   - text: String.t(); debug, info, warn, warning or error.
  #
  # Returns: {:ok, level} or {:error, message}.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: log_level("warn") returns {:ok, :warning}.
  defp log_level("debug"), do: {:ok, :debug}
  defp log_level("info"), do: {:ok, :info}
  defp log_level(level) when level in ["warn", "warning"], do: {:ok, :warning}
  defp log_level("error"), do: {:ok, :error}
  defp log_level(_), do: {:error, "AAAS_LOG_LEVEL must be debug, info, warn or error"}
end
