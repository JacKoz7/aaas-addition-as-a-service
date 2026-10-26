# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Http
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         The HTTP endpoint on port 8080 (Cowboy): GET /health and
#                  GET /metrics, problem details for anything else.
# Related Docs:    CLAUDE.md 6.1, services/carry/docs/API.md, RFC 9457

defmodule Carry.Http do
  @moduledoc """
  `GET /health` and `GET /metrics` on Cowboy.

  **Description:** `/health` checks the database (`Carry.Store.health/0`)
  and the broker (`Carry.Publisher.health/1`, 1 s) and answers
  `{"status": "ok" | "error", "checks": {"database": …, "broker": …}}`
  with 200, or 503 when a check failed. `/metrics` answers the Prometheus
  text format. Another method on these paths answers 405 with
  `Allow: GET`, another path 404, both as `application/problem+json`
  (RFC 9457). The listener accepts at most 256 connections and closes a
  connection after 10 s of silence; request bodies are never read.

  **Business Justification:** the Compose healthcheck, Consul (P5.1) and
  Prometheus (P7.1) read these endpoints (`CLAUDE.md` 6.1).

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Metrics`, `docs/API.md`.
  """

  @behaviour :cowboy_handler

  # The ranch listener of the HTTP endpoint.
  @listener :carry_http

  # The endpoints of the service.
  @paths ["/health", "/metrics"]

  @doc """
  The child specification of the HTTP listener.

  **Parameters:**
  - `port` — integer in `1..65535`.

  **Returns:** `Supervisor.child_spec()` of a ranch listener.

  **Errors:** none (a port in use fails the start of the child).

  **Side Effects:** none until started.

  **Complexity:** O(1).

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the listener is supervised with the
  service.

  **Example:** `Carry.Http.child_spec(8080)` as a child of the supervisor.

  **See Also:** `init/2`.
  """
  @spec child_spec(1..65_535) :: Supervisor.child_spec()
  def child_spec(port) do
    dispatch = :cowboy_router.compile([{:_, [{:_, __MODULE__, nil}]}])

    :ranch.child_spec(
      @listener,
      :ranch_tcp,
      %{socket_opts: [port: port], max_connections: 256},
      :cowboy_clear,
      %{env: %{dispatch: dispatch}, idle_timeout: 10_000, request_timeout: 10_000}
    )
  end

  @doc """
  Handles one request (callback of `:cowboy_handler`).

  **Parameters:**
  - `request` — `:cowboy_req.req()`.
  - `state` — `nil`.

  **Returns:** `{:ok, request, state}` after the reply is sent.

  **Errors:** none: every path and method gets an answer.

  **Side Effects:** sends one reply; `/health` reads Mnesia and sends a
  metadata request to the broker.

  **Complexity:** O(s) for s metric series.

  **Thread Safety:** safe; Cowboy runs each request in its own process.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** see the module documentation.

  **Example:** `GET /health` answers
  `{"status":"ok","checks":{"database":"ok","broker":"ok"}}`.

  **See Also:** `reply/2`.
  """
  @impl true
  @spec init(:cowboy_req.req(), nil) :: {:ok, :cowboy_req.req(), nil}
  def init(request, state) do
    {status, headers, body} = reply(:cowboy_req.method(request), :cowboy_req.path(request))
    {:ok, :cowboy_req.reply(status, headers, body, request), state}
  end

  @doc """
  The reply to a method and a path.

  **Parameters:**
  - `method` — `String.t()`; the request method.
  - `path` — `String.t()`; the request path, without the query.

  **Returns:** `{status, headers, body}`.

  **Errors:** none.

  **Side Effects:** `GET /health` checks the database and the broker.

  **Complexity:** O(s) for s metric series.

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the routing of the HTTP endpoint, testable
  without a socket.

  **Example:**

      iex> {404, _headers, body} = Carry.Http.reply("GET", "/x")
      iex> body
      ~s({"type":"about:blank","title":"Not Found","status":404,"detail":"no endpoint /x"})
      iex> {405, %{"allow" => "GET"}, _body} = Carry.Http.reply("POST", "/health")

  **See Also:** `health/0`.
  """
  @spec reply(String.t(), String.t()) :: {pos_integer(), map(), iodata()}
  def reply("GET", "/health"), do: health()

  def reply("GET", "/metrics"),
    do:
      {200, %{"content-type" => "text/plain; version=0.0.4; charset=utf-8"}, Carry.Metrics.render()}

  def reply(_method, path) when path in @paths,
    do: problem(405, "Method Not Allowed", "use GET for #{path}", %{"allow" => "GET"})

  def reply(_method, path), do: problem(404, "Not Found", "no endpoint #{path}", %{})

  # The health reply.
  #
  # Parameters: none.
  #
  # Returns: {200 or 503, headers, JSON body}.
  #
  # Errors: none. Side Effects: reads Mnesia; one broker metadata request.
  # Complexity: O(1). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: health() returns {200, headers, body} with both checks "ok".
  defp health do
    checks = [database: Carry.Store.health(), broker: Carry.Publisher.health(1_000)]
    healthy = Enum.all?(checks, fn {_name, result} -> result == :ok end)

    body =
      JSON.encode!(%{
        "status" => if(healthy, do: "ok", else: "error"),
        "checks" =>
          Map.new(checks, fn {name, result} ->
            {name, if(result == :ok, do: "ok", else: "error")}
          end)
      })

    {if(healthy, do: 200, else: 503), %{"content-type" => "application/json"}, body}
  end

  # A problem details reply (RFC 9457).
  #
  # Parameters:
  #   - status: integer; the HTTP status.
  #   - title: String.t().
  #   - detail: String.t().
  #   - headers: map; extra headers.
  #
  # Returns: {status, headers, JSON body}.
  #
  # Errors: none. Side Effects: none. Complexity: O(n).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: problem(404, "Not Found", "no endpoint /x", %{}).
  defp problem(status, title, detail, headers) do
    body =
      ~s({"type":"about:blank","title":#{JSON.encode!(title)},"status":#{status},"detail":#{JSON.encode!(detail)}})

    {status, Map.put(headers, "content-type", "application/problem+json"), body}
  end
end
