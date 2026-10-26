# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          tests/core_test.exs
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Unit tests of the pure modules: the carry arithmetic, its
#                  validation, the configuration, identifiers, trace
#                  context, the event and the log line.
# Related Docs:    Carry.Core, Carry.Config, contracts/proto/aaas/carry/v1

defmodule Carry.CoreTest do
  use ExUnit.Case, async: true

  alias Carry.{Config, Core, Event, Log, Trace, Uuid}

  @task "018f3c2e-7b1a-7c3d-9f00-0000000000aa"

  # The successor table of the digit services as a fake next_digit, which
  # also reports every asked digit to the test process.
  defp next do
    fn digit ->
      send(self(), {:asked, digit})
      {:ok, {elem({1, 2, 3, 4, 5, 6, 7, 8, 9, 0}, digit), digit == 9}}
    end
  end

  # The digits asked so far, in order.
  defp asked do
    receive do
      {:asked, digit} -> [digit | asked()]
    after
      0 -> []
    end
  end

  describe "propagate/3" do
    test "every number of the form x9…9 gets the carry it needs" do
      cases = [
        {[0], 1, [0, 1]},
        {[0, 1], 1, [0, 2]},
        {[0, 9], 1, [0, 0, 1]},
        {[0, 9, 9], 1, [0, 0, 0, 1]},
        {[0, 9, 9, 9, 9], 1, [0, 0, 0, 0, 0, 1]},
        {[0, 9, 9, 9, 9, 1], 1, [0, 0, 0, 0, 0, 2]},
        {[7, 3], 0, [8, 3]},
        {[5], 0, [6]}
      ]

      for {digits, position, expected} <- cases do
        assert {:ok, ^expected, _calls} = Core.propagate(digits, position, next())
      end
    end

    test "asks the digit services of the visited digits, in order" do
      assert {:ok, [0, 0, 0, 1], 3} = Core.propagate([0, 9, 9], 1, next())
      assert asked() == [9, 9, 0]
    end

    test "only digit-9 makes the propagation continue" do
      assert {:ok, [0, 4, 9], 1} = Core.propagate([0, 3, 9], 1, next())
      assert asked() == [3]
    end

    test "a carry past six digits creates the seventh" do
      assert {:ok, [0, 0, 0, 0, 0, 0, 1], 6} = Core.propagate([0, 9, 9, 9, 9, 9], 1, next())
    end

    test "a carrying successor of 0 is refused" do
      assert {:error, :new_digit_carries} = Core.propagate([0], 1, fn _ -> {:ok, {1, true}} end)
    end

    test "a failure of a digit service stops the propagation" do
      failing = fn
        9 -> {:ok, {0, true}}
        _ -> {:error, {:unavailable, "digit-1: down"}}
      end

      assert {:error, {:unavailable, "digit-1: down"}} = Core.propagate([0, 9, 1], 1, failing)
    end
  end

  describe "validate/3" do
    test "accepts the contract and refuses everything else" do
      assert :ok = Core.validate([0], 1, @task)
      assert :ok = Core.validate([9, 9, 9, 9, 9, 1], 6, @task)
      assert {:error, "digits must have 1 to 6 elements"} = Core.validate([], 0, @task)

      assert {:error, "digits must have 1 to 6 elements"} =
               Core.validate([0, 0, 0, 0, 0, 0, 0], 1, @task)

      assert {:error, "every digit must be in 0..9"} = Core.validate([0, 4_294_967_295], 1, @task)
      assert {:error, "position must be in 0..1"} = Core.validate([0], 2, @task)

      assert {:error, "task_id must be a lowercase UUIDv7"} =
               Core.validate([0], 1, "018f3c2e-7b1a-4c3d-9f00-0000000000aa")
    end
  end

  describe "Config.load/1" do
    test "reads every variable" do
      env = %{
        "AAAS_SERVICE" => "carry-x",
        "AAAS_HTTP_PORT" => "18080",
        "AAAS_GRPC_PORT" => "19090",
        "AAAS_KAFKA_BROKERS" => "a:1, b:2",
        "AAAS_DB_DIR" => "/tmp/m",
        "AAAS_MIGRATIONS_DIR" => "/tmp/mig",
        "AAAS_DIGIT_URL_TEMPLATE" => "http://d{digit}:8080/",
        "AAAS_LOG_LEVEL" => "debug",
        "AAAS_RETENTION_HOURS" => "2"
      }

      assert {:ok, config} = Config.load(env)
      assert config.service == "carry-x"
      assert {config.http_port, config.grpc_port} == {18_080, 19_090}
      assert config.kafka_brokers == [{~c"a", 1}, {~c"b", 2}]
      assert config.digit_url_template == "http://d{digit}:8080"
      assert {config.log_level, config.retention_hours} == {:debug, 2}
    end

    test "refuses invalid values" do
      for {name, value} <- [
            {"AAAS_HTTP_PORT", "x"},
            {"AAAS_GRPC_PORT", "65536"},
            {"AAAS_KAFKA_BROKERS", "redpanda"},
            {"AAAS_KAFKA_BROKERS", ""},
            {"AAAS_DIGIT_URL_TEMPLATE", "http://digit-9:8080"},
            {"AAAS_LOG_LEVEL", "loud"},
            {"AAAS_RETENTION_HOURS", "0"}
          ] do
        assert {:error, message} = Config.load(%{name => value})
        assert message =~ name
      end
    end
  end

  describe "identifiers, trace and event" do
    test "generated identifiers are distinct UUIDv7 in time order" do
      ids = for _ <- 1..100, do: Uuid.generate()
      assert Enum.all?(ids, &Uuid.v7?/1)
      assert length(Enum.uniq(ids)) == 100
    end

    test "an invalid traceparent starts a new trace" do
      for header <- [
            nil,
            "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
            "00-00000000000000000000000000000000-00f067aa0ba902b7-01",
            "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",
            "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01"
          ] do
        assert Trace.parse(header) == nil
        trace = Trace.child(Trace.parse(header))
        assert Trace.parse(Trace.render(trace)) == trace
      end
    end

    test "the event has the envelope fields and the payload" do
      trace = Trace.child(nil)
      text = Event.build(Uuid.generate(), 0, @task, trace, {[0, 9], 1}, [0, 0, 1])
      event = JSON.decode!(text)
      assert event["type"] == "aaas.carry.propagated"
      assert event["producer"] == "carry"
      assert event["payload"] == %{"digits" => [0, 9], "position" => 1, "result" => [0, 0, 1]}
      assert event["traceparent"] == Trace.render(trace)
    end

    test "log lines are JSON with the trace fields and library reports" do
      meta = %{time: 0, task_id: @task, trace_id: "t", span_id: "s"}
      line = Log.format(%{level: :warning, msg: {"~p", [:x]}, meta: meta}, %{service: "carry"})
      decoded = JSON.decode!(IO.iodata_to_binary(line))
      assert decoded["level"] == "warn"
      assert decoded["msg"] == "x"
      assert {decoded["taskId"], decoded["traceId"], decoded["spanId"]} == {@task, "t", "s"}

      report = %{level: :error, msg: {:report, %{a: 1}}, meta: %{time: 0, fields: [pid: self()]}}
      decoded = JSON.decode!(IO.iodata_to_binary(Log.format(report, %{service: "carry"})))
      assert decoded["msg"] == "%{a: 1}"
      assert decoded["pid"] =~ "#PID"
    end
  end
end
