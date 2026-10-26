# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          config/config.exs
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Build-time configuration: the Logger metadata keys of the
#                  service (rendered by Carry.Log at run time; listed here
#                  for the default formatter of the tests and for Credo).
#                  Run-time settings come from environment variables only
#                  (Carry.Config).
# Related Docs:    Carry.Log, Carry.Config, CLAUDE.md 6.1

import Config

config :logger, :default_formatter, metadata: [:task_id, :trace_id, :span_id, :fields]

if config_env() == :test do
  config :logger, level: :warning
end
