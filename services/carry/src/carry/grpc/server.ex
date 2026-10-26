# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Grpc.Server
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         The gRPC service aaas.carry.v1.CarryService on port 9090:
#                  decodes Propagate, runs it and maps failures to gRPC
#                  status codes.
# Related Docs:    contracts/proto/aaas/carry/v1/carry.proto, CLAUDE.md 4.3,
#                  ADR-0020, ADR-0032

defmodule Carry.Grpc.Server do
  @moduledoc """
  The server of `aaas.carry.v1.CarryService`.

  **Description:** `propagate/2` passes the request, the `traceparent`
  header and the caller's remaining deadline to `Carry.Propagation.run/2`
  and answers `PropagateResponse`. Failures become the statuses of the
  contract: `INVALID_ARGUMENT` for a request outside the contract,
  `UNAVAILABLE` when a digit service, Mnesia or the broker failed (the
  caller retries), `INTERNAL` when a digit service answered outside its
  contract.

  **Business Justification:** the gRPC contract of `CLAUDE.md` 4.3, called
  by `successor` (from P2.13b) for every carry.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Grpc.Endpoint`, `Carry.Propagation`.
  """

  use GRPC.Server, service: Aaas.Carry.V1.CarryService.Service

  alias Aaas.Carry.V1.{PropagateRequest, PropagateResponse}

  @doc """
  Serves `CarryService.Propagate`.

  **Parameters:**
  - `request` — `Aaas.Carry.V1.PropagateRequest`; digits, position and
    task identifier.
  - `stream` — `GRPC.Server.Stream`; the call (headers, deadline).

  **Returns:** `Aaas.Carry.V1.PropagateResponse` with the digits after
  the carry.

  **Errors:** raises `GRPC.RPCError` with `INVALID_ARGUMENT`,
  `UNAVAILABLE` or `INTERNAL` (see the module documentation).

  **Side Effects:** those of `Carry.Propagation.run/2`; counted by
  `Carry.Drain`.

  **Complexity:** O(d) network calls for d digits.

  **Thread Safety:** safe; each call runs in its own process.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the only method of the service.

  **Example:** a call with digits `[0, 9, 9]` and position 1 answers
  digits `[0, 0, 0, 1]` (999 + 1 = 1000).

  **See Also:** `status/1`.
  """
  @spec propagate(PropagateRequest.t(), GRPC.Server.Stream.t()) :: PropagateResponse.t()
  def propagate(%PropagateRequest{} = request, stream) do
    headers = GRPC.Stream.get_headers(stream)

    options = [
      template: Carry.Application.config().digit_url_template,
      traceparent: Map.get(headers, "traceparent"),
      remaining: GRPC.Server.Stream.remaining_ms(stream)
    ]

    call = %{digits: request.digits, position: request.position, task_id: request.task_id}

    case Carry.Drain.track(fn -> Carry.Propagation.run(call, options) end) do
      {:ok, result} -> %PropagateResponse{digits: result}
      {:error, {code, message}} -> raise GRPC.RPCError, status: status(code), message: message
    end
  end

  @doc """
  Tells the gRPC server whether an exception of a call is logged.

  **Description:** the failures this module raises as `GRPC.RPCError` are
  answers of the contract, already logged by `Carry.Propagation` as one
  JSON warning line; only other exceptions (bugs) are logged by the
  server, at error level.

  **Parameters:**
  - `report` — `GRPC.Server.Adapters.ReportException`; the exception.

  **Returns:** `boolean()`; `false` for a `GRPC.RPCError`.

  **Errors:** none.

  **Side Effects:** none.

  **Complexity:** O(1).

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** an invalid request is not an incident; the
  error level is kept for real errors.

  **Example:**

      iex> Carry.Grpc.Server.log_exception?(%{reason: %GRPC.RPCError{status: 3}})
      false

  **See Also:** `Carry.Application`.
  """
  @spec log_exception?(%{reason: term()}) :: boolean()
  def log_exception?(%{reason: %GRPC.RPCError{}}), do: false
  def log_exception?(_report), do: true

  @doc """
  The gRPC status code of a failure.

  **Parameters:**
  - `code` — `:invalid_argument`, `:unavailable` or `:internal`.

  **Returns:** non-negative integer; the status code.

  **Errors:** `FunctionClauseError` for another atom.

  **Side Effects:** none.

  **Complexity:** O(1).

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the error contract of `carry.proto`.

  **Example:**

      iex> Carry.Grpc.Server.status(:invalid_argument)
      3
      iex> Carry.Grpc.Server.status(:unavailable)
      14

  **See Also:** `propagate/2`.
  """
  @spec status(:invalid_argument | :unavailable | :internal) :: non_neg_integer()
  def status(:invalid_argument), do: GRPC.Status.invalid_argument()
  def status(:unavailable), do: GRPC.Status.unavailable()
  def status(:internal), do: GRPC.Status.internal()
end
