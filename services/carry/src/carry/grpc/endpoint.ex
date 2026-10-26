# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Grpc.Endpoint
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         The gRPC endpoint started by GRPC.Server.Supervisor on
#                  port 9090; it runs Carry.Grpc.Server.
# Related Docs:    Carry.Grpc.Server, ADR-0032

defmodule Carry.Grpc.Endpoint do
  @moduledoc """
  The gRPC endpoint of the carry service.

  **Description:** serves `Carry.Grpc.Server` without interceptors: the
  service logs and counts its calls itself. Its ranch listener is named
  `"Carry.Grpc.Endpoint"` (`listener/0`), which `Carry.Drain.stop/2`
  suspends at shutdown.

  **Business Justification:** the transport of the gRPC contract
  (`CLAUDE.md` 4.3, port 9090).

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Application`.
  """

  use GRPC.Endpoint

  run(Carry.Grpc.Server)

  @doc """
  The name of the ranch listener of the endpoint.

  **Parameters:** none.

  **Returns:** `String.t()`; the name given by the Cowboy adapter of the
  gRPC server (`inspect/1` of the endpoint module).

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(1).

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the graceful stop suspends this listener.

  **Example:**

      iex> Carry.Grpc.Endpoint.listener()
      "Carry.Grpc.Endpoint"

  **See Also:** `Carry.Drain.stop/2`.
  """
  @spec listener() :: String.t()
  def listener, do: inspect(__MODULE__)
end
