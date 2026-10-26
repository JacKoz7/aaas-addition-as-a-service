# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          .doctor.exs
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Configuration of Doctor (CLAUDE.md 6.5.4 for Elixir):
#                  100% @moduledoc, @doc and @spec coverage of every public
#                  module and function of the service. The generated gRPC
#                  modules (Aaas.*) are documented by their .proto files
#                  (ADR-0020) and skipped.
# Related Docs:    tools/doc_coverage.exs (private definitions), ADR-0032

%Doctor.Config{
  ignore_modules: [~r/^Aaas\./],
  ignore_paths: [],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 100,
  exception_moduledoc_required: true,
  raise: true,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
