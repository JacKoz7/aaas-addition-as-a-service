# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          tools/doc_coverage.exs
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Documentation coverage gate of the carry service: every
#                  module, function, macro, type and constant, private ones
#                  included, must be documented with the fields of CLAUDE.md
#                  6.5.3 (CLAUDE.md 6.5.4: 100%). Public definitions are
#                  documented by @moduledoc, @doc and @typedoc, private ones
#                  by a `#` comment block directly above them.
# Related Docs:    CLAUDE.md 6.5.3 and 6.5.4, ADR-0032
#
# Usage: elixir tools/doc_coverage.exs <file.ex> ...
# Prints every finding and a summary; exits with status 1 on any finding.

defmodule Carry.Tools.DocCoverage do
  @moduledoc """
  Checks the documentation of Elixir source files.

  **Description:** the files are parsed (not compiled) with their
  comments. A module needs a `@moduledoc` text with a summary and the
  fields Business Justification, Owner and Since. The first clause of a
  public function or macro needs a `@doc` text with a summary and the
  fields of `@function_labels` plus Business Justification; the first
  clause of a private one needs a `#` comment block, directly above it or
  above its `@spec`, with a summary and the fields of `@function_labels`.
  A public type needs a `@typedoc`, a private type and a constant (any
  other module attribute) a comment block with a summary. A field is a
  line or sentence starting with `**Field:**` (in docs) or `Field:` (in
  comments).

  **Business Justification:** `CLAUDE.md` 6.5.4 requires 100% coverage,
  private definitions included; Doctor and ExDoc see public definitions
  only.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `.doctor.exs`.
  """

  # The fields every function documents besides its summary.
  @function_labels [
    "Parameters",
    "Returns",
    "Errors",
    "Side Effects",
    "Complexity",
    "Thread Safety",
    "Owner",
    "Since",
    "Example"
  ]

  # Every field name of CLAUDE.md 6.5.3; a summary must not start with one.
  @all_labels [
    "Summary",
    "Description",
    "Business Justification",
    "Parameters",
    "Returns",
    "Errors",
    "Side Effects",
    "Complexity",
    "Thread Safety",
    "Owner",
    "Since",
    "Example",
    "See Also"
  ]

  # The fields every module documents besides its summary.
  @module_labels ["Business Justification", "Owner", "Since"]

  # Module attributes that are directives, not constants.
  @directives [
    :doc,
    :moduledoc,
    :typedoc,
    :spec,
    :impl,
    :behaviour,
    :callback,
    :macrocallback,
    :enforce_keys,
    :derive,
    :dialyzer,
    :compile,
    :type,
    :typep,
    :opaque
  ]

  @doc """
  Checks files and prints the findings.

  **Parameters:**
  - `files` — list of paths.

  **Returns:** `0` when every definition is documented, `1` otherwise or
  when no file is given.

  **Errors:** raises for a file that does not parse.

  **Side Effects:** reads the files; prints to stdout.

  **Complexity:** O(n) in the sources.

  **Thread Safety:** safe.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the doc-coverage stage fails on any
  finding.

  **Example:** `main(["src/carry/core.ex"])` returns 0.

  **See Also:** `check_source/2`.
  """
  @spec main([String.t()]) :: 0 | 1
  def main([]) do
    IO.puts("usage: elixir tools/doc_coverage.exs <file.ex> ...")
    1
  end

  def main(files) do
    results = Enum.map(files, &check_source(&1, File.read!(&1)))
    findings = Enum.flat_map(results, &elem(&1, 1))
    total = results |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    Enum.each(findings, &IO.puts/1)
    # A finding starts with file:line, and one line holds one definition.
    undocumented = findings |> Enum.map(&(&1 |> String.split(": ") |> hd())) |> Enum.uniq()

    IO.puts(
      "doc coverage: #{total - length(undocumented)}/#{total} definitions documented " <>
        "in #{length(files)} files"
    )

    if findings == [] and total > 0, do: 0, else: 1
  end

  @doc """
  Checks one source text.

  **Parameters:**
  - `file` — `String.t()`; the path, for the findings.
  - `source` — `String.t()`; the Elixir source.

  **Returns:** `{definitions, findings}`: the number of definitions
  checked and one text per finding, prefixed with `file:line`.

  **Errors:** raises a `SyntaxError` for a source that does not parse.

  **Side Effects:** none.

  **Complexity:** O(n) in the source.

  **Thread Safety:** pure.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the core of the gate, testable on strings.

  **Example:** `check_source("x.ex", "defmodule X do\\nend")` returns
  `{1, ["x.ex:1: X: no @moduledoc"]}`.

  **See Also:** `main/1`.
  """
  @spec check_source(String.t(), String.t()) :: {non_neg_integer(), [String.t()]}
  def check_source(file, source) do
    {ast, comments} = Code.string_to_quoted_with_comments!(source, file: file)
    by_line = Map.new(comments, &{&1.line, &1.text})

    {_ast, results} =
      Macro.prewalk(ast, [], fn
        {:defmodule, meta, [name, [do: body]]} = node, acc ->
          {node, [check_module(Macro.to_string(name), meta[:line], body, by_line) | acc]}

        node, acc ->
          {node, acc}
      end)

    results = Enum.reverse(results)

    {results |> Enum.map(&elem(&1, 0)) |> Enum.sum(),
     Enum.flat_map(results, fn {_count, findings} ->
       Enum.map(findings, fn {line, text} -> "#{file}:#{line}: #{text}" end)
     end)}
  end

  # Checks one module body.
  #
  # Description: walks the top-level expressions of the body in order,
  # remembering the @doc, @typedoc and @spec attributes that precede a
  # definition and the line where they start.
  #
  # Parameters:
  #   - name: String.t(); the module name.
  #   - line: positive integer; the line of defmodule.
  #   - body: the quoted body.
  #   - comments: map of line to comment text.
  #
  # Returns: {definitions, [{line, finding}]}.
  #
  # Errors: none. Side Effects: none. Complexity: O(n) in the body.
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: check_module("X", 1, nil, %{}) returns
  # {1, [{1, "X: no @moduledoc"}]}.
  defp check_module(name, line, body, comments) do
    expressions =
      case body do
        {:__block__, _, list} -> list
        nil -> []
        single -> [single]
      end

    initial = %{doc: nil, typedoc: nil, start: nil, seen: MapSet.new(), count: 1, findings: []}
    moduledoc = Enum.find_value(expressions, &moduledoc/1)

    state =
      Enum.reduce(expressions, initial, fn expression, state ->
        step(expression, state, name, comments)
      end)

    findings =
      case moduledoc do
        text when is_binary(text) -> labels(text, @module_labels, :doc, "#{name}")
        _ -> ["#{name}: no @moduledoc"]
      end

    {state.count, Enum.map(findings, &{line, &1}) ++ Enum.reverse(state.findings)}
  end

  # The @moduledoc text of an expression, or nil.
  #
  # Parameters:
  #   - expression: quoted expression.
  #
  # Returns: String.t() or nil.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: moduledoc(quote(do: @moduledoc("X."))) returns "X.".
  defp moduledoc({:@, _, [{:moduledoc, _, [text]}]}) when is_binary(text), do: text
  defp moduledoc(_expression), do: nil

  # Processes one expression of a module body.
  #
  # Parameters:
  #   - expression: quoted expression.
  #   - state: map with :doc, :typedoc, :start, :seen, :count, :findings.
  #   - module: String.t(); the module name.
  #   - comments: map of line to comment text.
  #
  # Returns: the updated state.
  #
  # Errors: none. Side Effects: none. Complexity: O(1) per expression.
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: step(quote(do: @doc("X.")), state, "M", %{}) remembers the
  # doc.
  defp step({:@, meta, [{:doc, _, [doc]}]}, state, _module, _comments),
    do: %{state | doc: doc, start: state.start || meta[:line]}

  defp step({:@, meta, [{:typedoc, _, [doc]}]}, state, _module, _comments),
    do: %{state | typedoc: doc, start: state.start || meta[:line]}

  defp step({:@, meta, [{attribute, _, _}]}, state, _module, _comments)
       when attribute in [:spec, :impl],
       do: %{state | start: state.start || meta[:line]}

  defp step({:@, meta, [{kind, _, [type]}]}, state, module, comments)
       when kind in [:type, :typep, :opaque] do
    name = "#{module}.#{type_name(type)}"

    finding =
      if kind == :typep,
        do: comment_finding(comments, meta[:line], [], name),
        else: doc_finding(state.typedoc, [], name, "@typedoc")

    record(state, meta[:line], finding)
  end

  defp step({:@, meta, [{attribute, _, [_value]}]}, state, module, comments)
       when attribute not in @directives do
    record(
      state,
      meta[:line],
      comment_finding(comments, meta[:line], [], "#{module} @#{attribute}")
    )
  end

  defp step({kind, meta, [head | _]}, state, module, comments)
       when kind in [:def, :defmacro, :defp, :defmacrop] do
    {name, arity} = signature(head)
    id = "#{module}.#{name}/#{arity}"

    if MapSet.member?(state.seen, id) do
      reset(state)
    else
      finding =
        if kind in [:def, :defmacro],
          do: doc_finding(state.doc, @function_labels ++ ["Business Justification"], id, "@doc"),
          else: comment_finding(comments, state.start || meta[:line], @function_labels, id)

      record(%{state | seen: MapSet.put(state.seen, id)}, meta[:line], finding)
    end
  end

  defp step(_expression, state, _module, _comments), do: reset(state)

  # Counts one definition and its findings, and forgets the pending
  # attributes.
  #
  # Parameters:
  #   - state: the walk state.
  #   - line: positive integer; the line of the definition.
  #   - findings: [String.t()].
  #
  # Returns: the updated state.
  #
  # Errors: none. Side Effects: none. Complexity: O(f).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: record(state, 3, []) adds one to the count.
  defp record(state, line, findings) do
    reset(%{
      state
      | count: state.count + 1,
        findings: Enum.reverse(Enum.map(findings, &{line, &1})) ++ state.findings
    })
  end

  # Forgets the pending attributes.
  #
  # Parameters:
  #   - state: the walk state.
  #
  # Returns: the state without :doc, :typedoc and :start.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: reset(%{state | doc: "X."}).doc is nil.
  defp reset(state), do: %{state | doc: nil, typedoc: nil, start: nil}

  # The findings of a @doc or @typedoc text.
  #
  # Parameters:
  #   - doc: String.t(), false or nil; the attribute value.
  #   - required: [String.t()]; the fields.
  #   - id: String.t(); the definition.
  #   - attribute: String.t(); "@doc" or "@typedoc".
  #
  # Returns: [String.t()].
  #
  # Errors: none. Side Effects: none. Complexity: O(n) in the text.
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: doc_finding(nil, [], "M.f/0", "@doc") returns
  # ["M.f/0: no @doc"].
  defp doc_finding(doc, required, id, _attribute) when is_binary(doc),
    do: labels(doc, required, :doc, id)

  defp doc_finding(_doc, _required, id, attribute), do: ["#{id}: no #{attribute}"]

  # The findings of the comment block that ends on the line above `line`.
  #
  # Parameters:
  #   - comments: map of line to comment text.
  #   - line: positive integer; the first line of the definition.
  #   - required: [String.t()]; the fields.
  #   - id: String.t(); the definition.
  #
  # Returns: [String.t()].
  #
  # Errors: none. Side Effects: none. Complexity: O(c) for c comment
  # lines. Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: comment_finding(%{}, 5, [], "M @x") returns
  # ["M @x: no comment"].
  defp comment_finding(comments, line, required, id) do
    block =
      Stream.iterate(line - 1, &(&1 - 1))
      |> Enum.take_while(&Map.has_key?(comments, &1))
      |> Enum.reverse()
      |> Enum.map_join("\n", &(comments[&1] |> String.trim_leading("#") |> String.trim()))

    if block == "", do: ["#{id}: no comment"], else: labels(block, required, :comment, id)
  end

  # The findings of a documentation text: its summary and its fields.
  #
  # Parameters:
  #   - text: String.t().
  #   - required: [String.t()]; the fields.
  #   - style: :doc (`**Field:**`) or :comment (`Field:`).
  #   - id: String.t(); the definition.
  #
  # Returns: [String.t()].
  #
  # Errors: none. Side Effects: none. Complexity: O(n * f).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: labels("X.", ["Owner"], :comment, "f") returns
  # ["f: no Owner field"].
  defp labels(text, required, style, id) do
    summary = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.find(&(&1 != ""))

    summary_finding =
      if summary == nil or
           Enum.any?(@all_labels, &String.starts_with?(summary, [&1 <> ":", "**" <> &1 <> ":"])),
         do: ["#{id}: the first line is not a summary"],
         else: []

    missing =
      for label <- required, not has_label?(text, label, style), do: "#{id}: no #{label} field"

    summary_finding ++ missing
  end

  # Whether a text has a field.
  #
  # Parameters:
  #   - text: String.t().
  #   - label: String.t(); the field name.
  #   - style: :doc or :comment.
  #
  # Returns: boolean.
  #
  # Errors: none. Side Effects: none. Complexity: O(n).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: has_label?("Owner: AEC.", "Owner", :comment) is true.
  defp has_label?(text, label, :doc), do: String.contains?(text, "**#{label}:**")

  defp has_label?(text, label, :comment),
    do: text =~ Regex.compile!("(^|\\n|\\. )#{Regex.escape(label)}:")

  # The name and arity of a function head.
  #
  # Parameters:
  #   - head: the quoted head, possibly with a guard.
  #
  # Returns: {atom, arity}.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: signature(quote(do: f(a, b) when a > b)) returns {:f, 2}.
  defp signature({:when, _, [head | _]}), do: signature(head)
  defp signature({name, _, args}) when is_list(args), do: {name, length(args)}
  defp signature({name, _, _context}), do: {name, 0}

  # The name of a type definition.
  #
  # Parameters:
  #   - type: the quoted `name :: definition`.
  #
  # Returns: String.t().
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: type_name(quote(do: t :: integer())) returns "t".
  defp type_name({:"::", _, [{name, _, _} | _]}), do: Atom.to_string(name)
  defp type_name(other), do: Macro.to_string(other)
end

System.halt(Carry.Tools.DocCoverage.main(System.argv()))
