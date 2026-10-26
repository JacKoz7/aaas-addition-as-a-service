# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          tests/test_helper.exs
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Starts ExUnit for the unit tests of the carry service; the
#                  application itself is not started (mix test --no-start),
#                  each test starts what it needs.
# Related Docs:    services/carry/README.md (Running and testing)

{:ok, _} = Application.ensure_all_started([:inets, :ranch, :cowboy, :mint, :grpc, :mnesia])
ExUnit.start()
