// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          tools/doc-coverage.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Documentation coverage gate of the Swift sources: every
//                  declaration in the symbol graphs, public and private, must
//                  carry a /// comment (CLAUDE.md 6.5.4).
// Related Docs:    services/digit-6/docs/SERVICE_CHARTER.md

// Documentation coverage gate of the Swift sources.
//
// DocC documents what carries a comment and does not fail on what does
// not, so it cannot prove coverage on its own. The compiler writes symbol
// graphs (JSON) for every declaration down to private access when built
// with -emit-symbol-graph -symbol-graph-minimum-access-level private.
// This script reads the symbol graph files given on the command line and
// requires a docComment on every symbol whose source location is under
// the directory given first (the service sources), skipping symbols the
// compiler synthesizes: those marked ::SYNTHESIZED:: and the implicit
// initializers (memberwise and init()), whose location is the line of the
// type declaration itself. It prints each finding and exits with status 1
// when any exists. Run with `swift tools/doc-coverage.swift <root> <file>...`.
//
// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.

import Foundation

/// The source root and the symbol graph files from the command line.
///
/// Owner: AEC. Since: digit-6 0.1.0.
let arguments = CommandLine.arguments.dropFirst()

/// Absolute path of the service sources; symbols elsewhere (SwiftNIO,
/// the standard library) are not checked.
///
/// Owner: AEC. Since: digit-6 0.1.0.
let root = arguments.first ?? "."

/// Number of symbols checked and of findings.
///
/// Owner: AEC. Since: digit-6 0.1.0.
var checked = 0
var missing: [String] = []

/// The position of a symbol: file URI and zero-based line.
///
/// - Parameter symbol: A symbol of a graph.
/// - Returns: "uri:line", or nil when the symbol has no location.
///
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
/// safe. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `position(of: symbol)`.
func position(of symbol: [String: Any]) -> String? {
  guard let location = symbol["location"] as? [String: Any], let uri = location["uri"] as? String
  else { return nil }
  return "\(uri):\((location["position"] as? [String: Any])?["line"] as? Int ?? -1)"
}

/// Kinds of the type declarations whose implicit initializers are skipped.
///
/// Owner: AEC. Since: digit-6 0.1.0.
let typeKinds: Set<String> = ["swift.struct", "swift.class", "swift.enum", "swift.actor"]

for path in arguments.dropFirst() {
  guard let data = FileManager.default.contents(atPath: path),
    let graph = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let symbols = graph["symbols"] as? [[String: Any]]
  else {
    print("\(path): not a symbol graph")
    exit(1)
  }
  let typePositions = Set(
    symbols.filter {
      typeKinds.contains((($0["kind"] as? [String: Any])?["identifier"] as? String) ?? "")
    }.compactMap(position(of:)))
  for symbol in symbols {
    let kind = (symbol["kind"] as? [String: Any])?["identifier"] as? String ?? ""
    if kind == "swift.init", let at = position(of: symbol), typePositions.contains(at) {
      continue
    }
    let identifier = (symbol["identifier"] as? [String: Any])?["precise"] as? String ?? ""
    guard let location = symbol["location"] as? [String: Any],
      let uri = location["uri"] as? String, uri.contains(root),
      !identifier.contains("::SYNTHESIZED::")
    else { continue }
    checked += 1
    if symbol["docComment"] == nil {
      let line = ((location["position"] as? [String: Any])?["line"] as? Int ?? -1) + 1
      let names = symbol["names"] as? [String: Any]
      missing.append(
        "\(uri.replacingOccurrences(of: "file://", with: "")):\(line): \(names?["title"] ?? "?")")
    }
  }
}
for finding in missing.sorted() {
  print("\(finding): undocumented")
}
print("doc-coverage: \(checked - missing.count)/\(checked) symbols documented")
exit(missing.isEmpty && checked > 0 ? 0 : 1)
