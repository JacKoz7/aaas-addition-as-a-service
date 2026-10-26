# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Publisher
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Publication of aaas.carry.propagated.v1 on Redpanda
#                  through brod, waiting for the broker's acknowledgement.
# Related Docs:    CLAUDE.md 4.2, ADR-0011, ADR-0032,
#                  services/carry/docs/DEPENDENCIES.md

defmodule Carry.Publisher do
  @moduledoc """
  The Kafka producer of the carry service.

  **Description:** one brod client, `:carry_kafka`, supervised by the
  brod application, connects to `AAAS_KAFKA_BROKERS` and starts the
  producer of the topic on first use.
  A message is keyed by `taskId` (brod's `:hash` partitioner) and is
  acknowledged by all in-sync replicas (`required_acks: -1`); the broker
  must answer within 1 s, and the producer retries a failed request twice
  after 100 ms. `publish/3` waits for the acknowledgement, so a call that
  answered success has its event on the broker. brod has no idempotent
  producer: a retried request can store a message twice, with the same
  `eventId`, which consumers deduplicate (`CLAUDE.md` 4.2).

  **Business Justification:** the propagation is answered only after its
  audit event is safe.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Event`, `Carry.Propagation`.
  """

  # The name of the brod client.
  @client :carry_kafka

  @doc """
  Starts the brod client under the supervisor of the brod application.

  **Description:** brod's own supervisor restarts a client that stopped
  (for example because no broker answered) after 5 s, without stopping
  the service: while the broker is down, `publish/3` and `health/1`
  return errors, and the calls answer `UNAVAILABLE`.

  **Parameters:**
  - `brokers` — list of `{host, port}`, host as a charlist.

  **Returns:** `:ok`, or `{:error, reason}`.

  **Errors:** `{:error, reason}` when the client cannot be registered
  (for example a second start).

  **Side Effects:** starts the client process, which connects to the
  brokers.

  **Complexity:** O(1).

  **Thread Safety:** call once at start-up.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** a broker outage delays additions; it must
  not stop the service.

  **Example:** `Carry.Publisher.start([{~c"redpanda", 9092}])` returns
  `:ok`.

  **See Also:** `publish/3`.
  """
  @spec start([{charlist(), pos_integer()}]) :: :ok | {:error, term()}
  def start(brokers) do
    config = [
      client_id: "carry",
      connect_timeout: 1_000,
      request_timeout: 2_000,
      restart_delay_seconds: 5,
      reconnect_cool_down_seconds: 1,
      auto_start_producers: true,
      default_producer_config: [
        required_acks: -1,
        ack_timeout: 1_000,
        max_retries: 2,
        retry_backoff_ms: 100
      ]
    ]

    :brod.start_client(brokers, @client, config)
  end

  @doc """
  Publishes one message and waits for the acknowledgement.

  **Parameters:**
  - `key` — `String.t()`; the message key (`taskId`).
  - `value` — `String.t()`; the event JSON.
  - `timeout` — positive integer; milliseconds to wait.

  **Returns:** `:ok`, or `{:error, reason}`.

  **Errors:** none (failures are return values): an unknown topic, a lost
  broker or a missing acknowledgement within `timeout`.

  **Side Effects:** sends one message to `aaas.carry.propagated.v1`.

  **Complexity:** O(n) in the size of the message.

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the audit event of every propagation.

  **Example:** `Carry.Publisher.publish(task_id, event, 1_000)` returns
  `:ok` with Redpanda up.

  **See Also:** `health/1`.
  """
  @spec publish(String.t(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def publish(key, value, timeout) do
    with {:ok, call_ref} <- :brod.produce(@client, Carry.Event.topic(), :hash, key, value) do
      case :brod.sync_produce_request(call_ref, timeout) do
        {:ok, _offset} -> :ok
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Checks that the broker answers a metadata request for the topic.

  **Parameters:**
  - `timeout` — positive integer; milliseconds to wait.

  **Returns:** `:ok`, or `{:error, reason}`.

  **Errors:** none.

  **Side Effects:** one metadata request through the client.

  **Complexity:** O(1).

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the `broker` check of `GET /health`.

  **Example:** `Carry.Publisher.health(1_000)` returns `:ok` with Redpanda
  up.

  **See Also:** `Carry.Http`.
  """
  @spec health(pos_integer()) :: :ok | {:error, term()}
  def health(timeout) do
    task =
      Task.async(fn ->
        try do
          :brod_client.get_metadata_safe(@client, Carry.Event.topic())
        catch
          :exit, reason -> {:error, reason}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, _metadata}} -> :ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:exit, reason} -> {:error, reason}
      nil -> {:error, :timeout}
    end
  end
end
