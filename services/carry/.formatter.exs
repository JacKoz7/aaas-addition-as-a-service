# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          .formatter.exs
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Configuration of `mix format`: the sources, tests and
#                  tools of the service, 100 columns (as the other services);
#                  the generated code of gen/ is left as generated.
# Related Docs:    CLAUDE.md 6.3, services/carry/Dockerfile (lint stage)

[
  inputs: ["mix.exs", ".formatter.exs", ".credo.exs", "{src,tests,tools}/**/*.{ex,exs}"],
  line_length: 100,
  import_deps: [:grpc_server, :protobuf]
]
