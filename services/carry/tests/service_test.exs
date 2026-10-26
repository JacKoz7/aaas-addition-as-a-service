# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          tests/service_test.exs
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Tests of the service with its real Mnesia database, fake
#                  digit services and a fake publisher: the store and its
#                  migrations, the digit client and its retries, the
#                  propagation log, gRPC over HTTP/2 and the HTTP endpoint.
# Related Docs:    Carry.Store, Carry.Digits, Carry.Propagation,
#                  contracts/proto/aaas/carry/v1/carry.proto

defmodule Carry.ServiceTest do
  use ExUnit.Case, async: false

  alias Aaas.Carry.V1.{CarryService, PropagateRequest}
  alias Carry.{Digits, Propagation, Store}
  alias Carry.Test.{FakeDigits, FakePublisher}

  @migrations Path.expand("../migrations", __DIR__)
  @task "018f3c2e-7b1a-7c3d-9f00-0000000000aa"

  setup_all do
    dir = Path.join(System.tmp_dir!(), "carry-test-#{System.unique_integer([:positive])}")
    {:ok, 1} = Store.open(dir, @migrations)
    template = FakeDigits.start()
    Application.put_env(:carry, :publisher, FakePublisher)
    start_supervised!({Carry.Metrics, "0.1.0"})
    Carry.Drain.init()
    :ok = Digits.start()

    config = %{elem(Carry.Config.load(%{}), 1) | digit_url_template: template, grpc_port: 0}
    :persistent_term.put({Carry.Application, :config}, config)
    %{dir: dir, template: template}
  end

  setup do
    FakePublisher.reset()
    FakeDigits.reset()
    :mnesia.clear_table(:carry_propagations)
    :ok
  end

  # A unique task identifier for one test.
  defp task, do: Carry.Uuid.generate()

  # A deadline 2 s from now.
  defp deadline, do: System.monotonic_time(:millisecond) + 2_000

  describe "store" do
    test "a reopened database applies no migration and keeps the documentation", %{dir: dir} do
      assert {:ok, 0} = Store.open(dir, @migrations)
      properties = :mnesia.table_info(:carry_propagations, :user_properties)

      assert {:aaas_documentation, %{"attributes" => attributes}} =
               List.keyfind(properties, :aaas_documentation, 0)

      assert Map.keys(attributes) |> Enum.sort() ==
               Enum.sort(
                 Enum.map(:mnesia.table_info(:carry_propagations, :attributes), &Atom.to_string/1)
               )

      assert :mnesia.table_info(:carry_propagations, :storage_type) == :disc_only_copies

      assert [{:carry_migrations, "0001_propagations.json", _at, _description}] =
               :mnesia.dirty_read(:carry_migrations, "0001_propagations.json")
    end

    test "a missing migrations directory stops the start", %{dir: dir} do
      assert {:error, message} = Store.open(dir, "/nonexistent")
      assert message =~ "migrations directory"
      assert {:ok, 0} = Store.open(dir, @migrations)
    end

    test "record keeps the first entry of a key and prune removes old ones" do
      entry = %{
        task_id: @task,
        digits: [0, 9],
        position: 1,
        result: [0, 0, 1],
        event_id: "e1",
        event: "{}",
        propagated_at: 1_000,
        trace_id: "t"
      }

      assert {:ok, :created, ^entry} = Store.record(entry)
      assert {:ok, :existing, ^entry} = Store.record(%{entry | event_id: "e2"})
      assert {:ok, ^entry} = Store.lookup({@task, [0, 9], 1})
      assert :none = Store.lookup({@task, [0, 9], 0})
      newer = %{entry | digits: [0, 1], result: [0, 2], propagated_at: 5_000}
      {:ok, :created, _} = Store.record(newer)
      assert {:ok, 1} = Store.prune(2_000)
      assert :none = Store.lookup({@task, [0, 9], 1})
      assert {:ok, ^newer} = Store.lookup({@task, [0, 1], 1})
      assert :ok = Store.health()
    end

    test "the retention job deletes records older than the retention" do
      old = System.system_time(:millisecond) - 3 * 3_600_000

      entry = %{
        task_id: @task,
        digits: [0, 9],
        position: 1,
        result: [0, 0, 1],
        event_id: "e1",
        event: "{}",
        propagated_at: old,
        trace_id: "t"
      }

      {:ok, :created, _} = Store.record(entry)

      {:ok, :created, _} =
        Store.record(%{entry | digits: [0, 1], propagated_at: System.system_time(:millisecond)})

      assert {:noreply, 2} = Carry.Retention.handle_info(:prune, 2)
      assert :none = Store.lookup({@task, [0, 9], 1})
      assert {:ok, _} = Store.lookup({@task, [0, 1], 1})
      assert IO.iodata_to_binary(Carry.Metrics.render()) =~ "carry_retention_deleted_total 1"
    end

    test "concurrent records of one key store one entry" do
      entries =
        for n <- 1..20 do
          %{
            task_id: @task,
            digits: [0, 9],
            position: 1,
            result: [0, 0, 1],
            event_id: "e#{n}",
            event: "{}",
            propagated_at: 1,
            trace_id: "t"
          }
        end

      results =
        entries
        |> Task.async_stream(&Store.record/1)
        |> Enum.map(fn {:ok, {:ok, status, stored}} -> {status, stored.event_id} end)

      assert Enum.count(results, &match?({:created, _}, &1)) == 1
      assert results |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 1
    end
  end

  describe "digit client" do
    test "reads the contract answer", %{template: template} do
      assert {:ok, {0, true}} = Digits.next(template, 9, deadline: deadline())
      assert {:ok, {8, false}} = Digits.next(template, 7, deadline: deadline())
    end

    test "retries 5xx answers and timeouts", %{template: template} do
      FakeDigits.script(9, [{503, "{}"}, :sleep, :default])
      assert {:ok, {0, true}} = Digits.next(template, 9, deadline: deadline())
      assert FakeDigits.requests(9) == 3
    end

    test "gives up after three attempts", %{template: template} do
      FakeDigits.script(4, [{503, "{}"}, {500, "{}"}, {503, "{}"}, :default])
      assert {:error, {:unavailable, detail}} = Digits.next(template, 4, deadline: deadline())
      assert detail =~ "digit-4"
      assert FakeDigits.requests(4) == 3
    end

    test "does not retry an answer outside the contract", %{template: template} do
      FakeDigits.script(3, [{200, ~s({"digit":4,"next":5,"carry":false})}])
      assert {:error, {:invalid_answer, _}} = Digits.next(template, 3, deadline: deadline())
      FakeDigits.script(3, [{404, "{}"}])

      assert {:error, {:invalid_answer, "digit-3 answered HTTP 404"}} =
               Digits.next(template, 3, deadline: deadline())

      assert FakeDigits.requests(3) == 2
    end

    test "stops at the deadline", %{template: template} do
      FakeDigits.script(2, [:sleep, :sleep, :sleep])
      started = System.monotonic_time(:millisecond)
      assert {:error, {:unavailable, _}} = Digits.next(template, 2, deadline: started + 300)
      assert System.monotonic_time(:millisecond) - started < 450
    end

    test "an unreachable service is unavailable" do
      assert {:error, {:unavailable, _}} =
               Digits.next("http://127.0.0.1:1/{digit}", 5, deadline: deadline())
    end
  end

  describe "propagation" do
    test "computes, records and publishes once; a retry replays the event", %{template: template} do
      task = task()
      request = %{digits: [0, 9, 9], position: 1, task_id: task}
      trace = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
      assert {:ok, [0, 0, 0, 1]} = Propagation.run(request, template: template, traceparent: trace)
      assert {FakeDigits.requests(9), FakeDigits.requests(0)} == {2, 1}
      [{^task, event}] = FakePublisher.events()
      assert JSON.decode!(event)["traceparent"] =~ "00-4bf92f3577b34da6a3ce929d0e0e4736-"

      assert {:ok, [0, 0, 0, 1]} = Propagation.run(request, template: template)
      assert {FakeDigits.requests(9), FakeDigits.requests(0)} == {2, 1}
      assert [{^task, ^event}, {^task, ^event}] = FakePublisher.events()
    end

    test "a broker failure answers unavailable and the retry publishes the stored event", %{
      template: template
    } do
      request = %{digits: [0, 9], position: 1, task_id: task()}
      FakePublisher.fail(1)

      assert {:error, {:unavailable, "broker: :broker_down"}} =
               Propagation.run(request, template: template)

      assert FakePublisher.events() == []
      assert {:ok, [0, 0, 1]} = Propagation.run(request, template: template)
      assert [{_, _}] = FakePublisher.events()
      assert FakeDigits.requests(9) == 1
    end

    test "nothing is recorded when a digit service is down", %{template: template} do
      request = %{digits: [0, 1], position: 1, task_id: task()}
      FakeDigits.script(1, [{503, "{}"}, {503, "{}"}, {503, "{}"}])
      assert {:error, {:unavailable, _}} = Propagation.run(request, template: template)
      assert :none = Store.lookup({request.task_id, [0, 1], 1})
      assert {:ok, [0, 2]} = Propagation.run(request, template: template)
    end

    test "invalid requests ask nobody", %{template: template} do
      assert {:error, {:invalid_argument, _}} =
               Propagation.run(%{digits: [0], position: 1, task_id: "x"}, template: template)

      assert {:error, {:invalid_argument, _}} =
               Propagation.run(%{digits: [0], position: 2, task_id: task()}, template: template)

      assert Enum.all?(0..9, &(FakeDigits.requests(&1) == 0))
    end
  end

  describe "gRPC" do
    setup do
      port = 19_000 + rem(System.unique_integer([:positive]), 1_000)

      start_supervised!(
        {GRPC.Server.Supervisor,
         endpoint: Carry.Grpc.Endpoint,
         port: port,
         start_server: true,
         max_body_size: 4_096,
         exception_log_filter: {Carry.Grpc.Server, :log_exception?}}
      )

      {:ok, channel} = GRPC.Stub.connect("127.0.0.1:#{port}", adapter: GRPC.Client.Adapters.Mint)
      %{channel: channel}
    end

    test "Propagate answers the digits after the carry", %{channel: channel} do
      request = %PropagateRequest{digits: [0, 9, 9, 9, 9], position: 1, task_id: task()}
      assert {:ok, response} = CarryService.Stub.propagate(channel, request)
      assert response.digits == [0, 0, 0, 0, 0, 1]
    end

    test "status codes follow the contract", %{channel: channel} do
      assert {:error, %GRPC.RPCError{status: 3}} =
               CarryService.Stub.propagate(channel, %PropagateRequest{
                 digits: [0],
                 position: 1,
                 task_id: ""
               })

      FakeDigits.script(9, [{503, "{}"}, {503, "{}"}, {503, "{}"}])

      assert {:error, %GRPC.RPCError{status: 14}} =
               CarryService.Stub.propagate(channel, %PropagateRequest{
                 digits: [0, 9],
                 position: 1,
                 task_id: task()
               })

      FakeDigits.script(9, [{200, ~s({"digit":9,"next":10,"carry":true})}])

      assert {:error, %GRPC.RPCError{status: 13}} =
               CarryService.Stub.propagate(channel, %PropagateRequest{
                 digits: [0, 9],
                 position: 1,
                 task_id: task()
               })
    end
  end

  describe "HTTP" do
    test "health, metrics and problems" do
      assert {503, _, body} = Carry.Http.reply("GET", "/health")

      assert JSON.decode!(body) == %{
               "status" => "error",
               "checks" => %{"database" => "ok", "broker" => "error"}
             }

      {200, %{"content-type" => "text/plain" <> _}, metrics} = Carry.Http.reply("GET", "/metrics")
      metrics = IO.iodata_to_binary(metrics)
      assert metrics =~ ~s(carry_build_info{version="0.1.0"} 1)
      assert metrics =~ ~s(carry_propagation_duration_seconds_bucket{le="+Inf"})
      assert {405, %{"allow" => "GET"}, _} = Carry.Http.reply("DELETE", "/metrics")
    end
  end
end
