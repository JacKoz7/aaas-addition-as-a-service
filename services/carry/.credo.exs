# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          .credo.exs
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Configuration of Credo, the linter of the lint stage: all
#                  default checks in strict mode over the sources, tests and
#                  tools; the generated code of gen/ is not linted
#                  (ADR-0020), and specs are required on every public
#                  function.
# Related Docs:    CLAUDE.md 6.3, services/carry/Dockerfile (lint stage)

%{
  configs: [
    %{
      name: "default",
      files: %{included: ["mix.exs", "src/", "tests/", "tools/"], excluded: ["gen/"]},
      strict: true,
      checks: %{
        extra: [{Credo.Check.Readability.Specs, []}]
      }
    }
  ]
}
