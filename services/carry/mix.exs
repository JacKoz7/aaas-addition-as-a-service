# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.MixProject
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Mix project of the carry service: sources, pinned
#                  dependencies, the release and the ExDoc settings.
# Related Docs:    services/carry/README.md, services/carry/Dockerfile,
#                  ADR-0032

defmodule Carry.MixProject do
  @moduledoc """
  The Mix project of the carry service.

  **Description:** the sources are `src/` and the generated gRPC code of
  `gen/` (copied from `contracts/gen/elixir` by the Dockerfile); the
  tests are `tests/`, with the test doubles of `tests/support` compiled in
  the test environment. Every dependency is pinned to one version, and
  `mix.lock` pins its checksum. The release `carry` loads Mnesia without
  starting it (`Carry.Store` starts it on its own directory) and leaves
  out the build tools.

  **Business Justification:** reproducible builds of the service.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Application`, ADR-0032.
  """

  use Mix.Project

  @doc """
  The project definition (callback of `Mix.Project`).

  **Parameters:** none.

  **Returns:** keyword list of project settings.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(1).

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** read by every `mix` task.

  **Example:** `Mix.Project.config()[:version]` is `"0.1.0"`.

  **See Also:** `application/0`.
  """
  @spec project() :: keyword()
  def project do
    [
      app: :carry,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: ["tests"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [carry: [include_executables_for: [:unix]]],
      name: "carry",
      docs: [
        main: "api-reference",
        source_url: "https://github.com/JacKoz7/AaaS---Addition-as-a-Service",
        filter_modules: ~r/^Elixir\.Carry\./
      ]
    ]
  end

  @doc """
  The OTP application (callback of `Mix.Project`).

  **Parameters:** none.

  **Returns:** keyword list: the extra applications and the start module.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(1).

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Description:** Mnesia is an included application: it is loaded with
  the service but not started by the release, because `Carry.Store`
  starts it after pointing it at `AAAS_DB_DIR`.

  **Business Justification:** inets (`:httpc`) is part of Erlang/OTP, not
  a Hex package.

  **Example:** `mix run` starts `Carry.Application`.

  **See Also:** `project/0`.
  """
  @spec application() :: keyword()
  def application do
    [
      extra_applications: [:logger, :inets],
      included_applications: [:mnesia],
      mod: {Carry.Application, []}
    ]
  end

  # The compiled source directories of an environment.
  #
  # Parameters:
  #   - env: atom; the Mix environment.
  #
  # Returns: [String.t()]; tests/support is added for :test.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: elixirc_paths(:prod) returns ["src", "gen"].
  defp elixirc_paths(:test), do: ["src", "gen", "tests/support"]
  defp elixirc_paths(_env), do: ["src", "gen"]

  # The dependencies, each pinned to one version.
  #
  # Description: grpc_server serves gRPC (Cowboy); grpc is needed at
  # compile time by the generated client stub and as the client of the
  # tests (with Mint); protobuf runs the generated messages; brod
  # publishes to Kafka. credo, doctor and ex_doc are tools.
  #
  # Parameters: none.
  #
  # Returns: list of dependency tuples.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: deps() contains {:brod, "4.7.0"}.
  defp deps do
    [
      {:grpc_server, "1.0.5"},
      {:grpc, "1.0.5"},
      {:protobuf, "0.17.1"},
      {:brod, "4.7.0"},
      {:mint, "1.11.0", only: :test},
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:doctor, "0.23.0", only: :dev, runtime: false},
      {:ex_doc, "0.40.4", only: :dev, runtime: false}
    ]
  end
end
