# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          tests/doctest_test.exs
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Runs the `iex>` examples of every documented module as
#                  tests (CLAUDE.md 6.5.3: examples run where the language
#                  supports doctests).
# Related Docs:    CLAUDE.md 6.5.3, services/carry/README.md

defmodule Carry.DoctestTest do
  use ExUnit.Case, async: false

  doctest Carry.Uuid
  doctest Carry.Trace
  doctest Carry.Core
  doctest Carry.Config
  doctest Carry.Log
  doctest Carry.Event
  doctest Carry.Digits
  doctest Carry.Http
  doctest Carry.Drain
  doctest Carry.Grpc.Server
  doctest Carry.Grpc.Endpoint
end
