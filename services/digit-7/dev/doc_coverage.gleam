//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          dev/doc_coverage.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Documentation coverage check of the service's Gleam
////                  sources (CLAUDE.md 6.5.4): a module comment in every
////                  module and a doc comment on every definition, public
////                  and private.
//// Related Docs:    CLAUDE.md 6.5.3, CLAUDE.md 6.5.4, ADR-0009, ADR-0029
////
//// The doc-coverage gate of the digit-7 service.
////
//// `gleam docs build` documents public definitions only and does not
//// fail on missing comments, so this tool parses every module with
//// `glance` and requires:
////
//// - a module comment (`////`) that continues after the file header;
//// - a `///` comment directly above every function, external, constant,
////   type alias and custom type, public or private (attributes such as
////   `@external` may stand between the comment and the definition);
//// - a `///` comment directly above every constructor of a custom type.
////
//// It prints each gap as `file:line: kind name`, the totals, and exits
//// with status 1 when anything is undocumented. Run it with
//// `gleam run -m doc_coverage` from the package root.

import glance
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/erlang/charlist.{type Charlist}
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string

/// One documentable item of a module.
///
/// Thread Safety: an immutable value. Owner: Arithmetic Excellence Center
/// (AEC). Since: digit-7 0.1.0.
pub type Item {
  /// Kind (`fn`, `const`, `type`, `alias`, `constructor`, `module`),
  /// name, 1-based line and whether it is documented.
  Item(kind: String, name: String, line: Int, documented: Bool)
}

/// `filelib:wildcard/1`: the paths matching a glob.
///
/// Parameters: `pattern` — the glob, as a charlist. Returns: the paths
/// as charlists.
/// Errors: none. Side Effects: reads directories. Complexity: O(n).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `wildcard("src/**/*.gleam")`.
@external(erlang, "filelib", "wildcard")
fn wildcard(pattern: Charlist) -> List(Charlist)

/// `file:read_file/1`.
///
/// Parameters: `path` — the file. Returns: its bytes or the reason.
/// Errors: as the result says. Side Effects: reads the file.
/// Complexity: O(n). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `read_file("src/digit7.gleam")`.
@external(erlang, "file", "read_file")
fn read_file(path: String) -> Result(BitArray, Dynamic)

/// `erlang:halt/1`.
///
/// Parameters: `status` — the exit status. Returns: never. Errors: none.
/// Side Effects: ends the runtime. Complexity: O(1). Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `halt(1)`.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// The 1-based line of a byte offset.
///
/// Parameters: `source` — the file bytes; `offset` — a byte offset.
/// Returns: the line number. Errors: none. Side Effects: none.
/// Complexity: O(n). Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `line_of(<<"a\nb":utf8>>, 2) == 2`.
pub fn line_of(source: BitArray, offset: Int) -> Int {
  let prefix = result.unwrap(bit_array.slice(source, 0, offset), <<>>)
  1 + count_line_feeds(prefix, 0)
}

/// The number of line feeds in a binary.
///
/// Parameters: `bytes` — the binary; `count` — the count so far.
/// Returns: the count. Errors: none. Side Effects: none.
/// Complexity: O(n). Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `count_line_feeds(<<"a\n":utf8>>, 0) == 1`.
fn count_line_feeds(bytes: BitArray, count: Int) -> Int {
  case bytes {
    <<10, rest:bytes>> -> count_line_feeds(rest, count + 1)
    <<_, rest:bytes>> -> count_line_feeds(rest, count)
    _ -> count
  }
}

/// Whether the definition starting on a line has a doc comment above it.
///
/// Description: walks up from the line before, over attribute lines
/// (starting with `@`), and requires a line starting with `///` (not
/// `////`).
/// Parameters: `lines` — the file lines; `line` — the 1-based line of the
/// definition. Returns: True when documented. Errors: none.
/// Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `documented(["/// Doc.", "pub fn f() {"], 2) == True`.
pub fn documented(lines: List(String), line: Int) -> Bool {
  lines
  |> list.take(line - 1)
  |> list.reverse
  |> list.map(string.trim)
  |> list.drop_while(fn(text) { string.starts_with(text, "@") })
  |> list.first
  |> result.map(fn(text) {
    string.starts_with(text, "///") && !string.starts_with(text, "////")
  })
  |> result.unwrap(False)
}

/// Whether the module comment continues after the file header.
///
/// Description: the header ends with the `Related Docs:` field and its
/// continuation lines; an empty `////` line and a `////` line with text
/// must follow.
/// Parameters: `lines` — the file lines. Returns: True when the module is
/// described. Errors: none. Side Effects: none. Complexity: O(n).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `module_documented(lines)`.
pub fn module_documented(lines: List(String)) -> Bool {
  let after =
    lines
    |> list.drop_while(fn(text) {
      !string.starts_with(text, "//// Related Docs:")
    })
    |> list.drop(1)
    |> list.drop_while(fn(text) { string.starts_with(text, "////" <> "    ") })
  case after {
    ["////", text, ..] -> string.starts_with(text, "//// ") && text != "//// "
    _ -> False
  }
}

/// The line of a constructor inside the source of its custom type.
///
/// Parameters: `lines` — the file lines; `from`, `to` — the lines of the
/// type; `name` — the constructor. Returns: the first line in the range
/// whose text starts with the name followed by `(`, a space or nothing.
/// Errors: `Nil` when not found. Side Effects: none. Complexity: O(n).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `constructor_line(lines, 3, 9, "Debug")`.
fn constructor_line(
  lines: List(String),
  from: Int,
  to: Int,
  name: String,
) -> Result(Int, Nil) {
  lines
  |> list.index_map(fn(text, index) { #(index + 1, string.trim(text)) })
  |> list.find(fn(entry) {
    let #(number, text) = entry
    number > from
    && number <= to
    && {
      text == name
      || string.starts_with(text, name <> "(")
      || string.starts_with(text, name <> " ")
    }
  })
  |> result.map(fn(entry) { entry.0 })
}

/// The documentable items of one module.
///
/// Parameters: `source` — the file bytes. Returns: the items with their
/// documentation status. Errors: the parse error as text.
/// Side Effects: none. Complexity: O(n · d) for d definitions.
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `items(source)`.
pub fn items(source: BitArray) -> Result(List(Item), String) {
  use text <- result.try(
    bit_array.to_string(source) |> result.replace_error("not UTF-8"),
  )
  use parsed <- result.try(
    glance.module(text) |> result.map_error(string.inspect),
  )
  let lines = string.split(text, "\n")
  let item = fn(kind, name, start) {
    let line = line_of(source, start)
    Item(kind, name, line, documented(lines, line))
  }
  let functions =
    list.map(parsed.functions, fn(definition) {
      let function = definition.definition
      item("fn", function.name, function.location.start)
    })
  let constants =
    list.map(parsed.constants, fn(definition) {
      let constant = definition.definition
      item("const", constant.name, constant.location.start)
    })
  let aliases =
    list.map(parsed.type_aliases, fn(definition) {
      let alias = definition.definition
      item("alias", alias.name, alias.location.start)
    })
  let types =
    list.flat_map(parsed.custom_types, fn(definition) {
      let custom = definition.definition
      let from = line_of(source, custom.location.start)
      let to = line_of(source, custom.location.end)
      let constructors =
        list.map(custom.variants, fn(variant) {
          case constructor_line(lines, from, to, variant.name) {
            Ok(line) ->
              Item("constructor", variant.name, line, documented(lines, line))
            Error(Nil) -> Item("constructor", variant.name, from, False)
          }
        })
      [item("type", custom.name, custom.location.start), ..constructors]
    })
  Ok([
    Item("module", "", 1, module_documented(lines)),
    ..list.flatten([functions, constants, aliases, types])
  ])
}

/// Check every Gleam file of the package and exit with the result.
///
/// Business Justification: CLAUDE.md 6.5.4 requires 100% documentation
/// coverage, private definitions included.
/// Parameters: none. Returns: never (halts with 0 or 1). Errors: none.
/// Side Effects: reads `src/`, `test/` and `dev/`; prints gaps and totals.
/// Complexity: O(total source size). Thread Safety: called once.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `gleam run -m doc_coverage`.
pub fn main() -> Nil {
  let files =
    ["src/**/*.gleam", "test/**/*.gleam", "dev/**/*.gleam"]
    |> list.flat_map(fn(pattern) { wildcard(charlist.from_string(pattern)) })
    |> list.map(charlist.to_string)
  let results =
    list.map(files, fn(path) {
      case read_file(path) |> result.replace_error("unreadable") {
        Error(reason) -> #(path, Error(reason))
        Ok(source) -> #(path, items(source))
      }
    })
  let failures =
    list.filter_map(results, fn(entry) {
      case entry {
        #(path, Error(reason)) -> Ok(path <> ": cannot parse: " <> reason)
        _ -> Error(Nil)
      }
    })
  let all =
    list.flat_map(results, fn(entry) {
      case entry {
        #(path, Ok(found)) -> list.map(found, fn(item) { #(path, item) })
        _ -> []
      }
    })
  let missing = list.filter(all, fn(entry) { !{ entry.1 }.documented })
  list.each(failures, io.println)
  list.each(missing, fn(entry) {
    let #(path, item) = entry
    io.println(
      path
      <> ":"
      <> int.to_string(item.line)
      <> ": undocumented "
      <> item.kind
      <> " "
      <> item.name,
    )
  })
  let total = list.length(all)
  io.println(
    "doc-coverage: "
    <> int.to_string(total - list.length(missing))
    <> "/"
    <> int.to_string(total)
    <> " items documented in "
    <> int.to_string(list.length(files))
    <> " files",
  )
  case missing, failures, files {
    [], [], [_, ..] -> halt(0)
    _, _, _ -> halt(1)
  }
}
