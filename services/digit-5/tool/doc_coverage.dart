// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          tool/doc_coverage.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Documentation coverage gate of the Dart sources: every
//                  library, type, member, constant and variable, public
//                  and private, must carry a /// comment (CLAUDE.md 6.5.4).
// Related Docs:    services/digit-5/Dockerfile (doc-coverage stage),
//                  CLAUDE.md 6.5.3, ADR-0027

/// Documentation coverage gate of the Dart sources.
///
/// The lint `public_member_api_docs` checks public members only, and
/// dartdoc does not fail on missing comments. This tool parses each file
/// given on the command line with package:analyzer and requires a
/// documentation comment on the library directive and on every
/// declaration: classes, mixins, enums and their values, extensions,
/// typedefs, top-level functions and variables, constructors, methods,
/// getters, setters and fields, public and private. Local functions and
/// variables inside bodies are not declarations of the API and are not
/// checked. It prints each finding and exits with status 1 when any
/// exists.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Collects the declarations of one file that have no documentation
/// comment.
///
/// Business Justification: one finding per undocumented declaration.
///
/// Thread Safety: one instance per file. Owner: Arithmetic Excellence
/// Center (AEC). Since: digit-5 0.1.0.
class _Collector extends GeneralizingAstVisitor<void> {
  /// Create a collector for one parsed file.
  ///
  /// Parameters:
  /// - [_unit]: the parsed file, for line numbers.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// one instance per file. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `unit.accept(_Collector(unit));`
  ///
  /// See Also: [main].
  _Collector(this._unit);

  /// The parsed file.
  final CompilationUnit _unit;

  /// Number of declarations checked.
  int checked = 0;

  /// Line numbers and source excerpts of the undocumented declarations.
  final List<String> missing = [];

  /// Record one declaration.
  ///
  /// Parameters:
  /// - [node]: the declaration.
  /// - [comment]: its documentation comment, null when absent.
  ///
  /// Errors: none. Side Effects: updates [checked] and [missing].
  /// Complexity: O(1). Thread Safety: one instance per file. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `_record(node, node.documentationComment);`
  ///
  /// See Also: [visitDeclaration].
  void _record(AstNode node, Comment? comment) {
    checked++;
    if (comment == null) {
      final line = _unit.lineInfo.getLocation(node.offset).lineNumber;
      final text = node.toSource();
      missing.add('$line: ${text.length > 60 ? text.substring(0, 60) : text}');
    }
  }

  /// Check the library directive.
  ///
  /// Parameters:
  /// - [node]: the directive.
  ///
  /// Errors: none. Side Effects: records the directive. Complexity: O(1).
  /// Thread Safety: one instance per file. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: called by the visitor.
  ///
  /// See Also: [_record].
  @override
  void visitLibraryDirective(LibraryDirective node) =>
      _record(node, node.documentationComment);

  /// Check one declaration, then its members.
  ///
  /// Description: variables are checked through their field or top-level
  /// declaration (which carries the comment), type parameters are not
  /// declarations of the API, and declarations inside function bodies are
  /// skipped.
  ///
  /// Parameters:
  /// - [node]: the declaration.
  ///
  /// Errors: none. Side Effects: records the declaration. Complexity: O(n)
  /// in the members. Thread Safety: one instance per file. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: called by the visitor.
  ///
  /// See Also: [_record].
  @override
  void visitDeclaration(Declaration node) {
    if (node is VariableDeclaration || node is TypeParameter) {
      return;
    }
    if (node.thisOrAncestorOfType<FunctionBody>() != null) {
      return;
    }
    _record(node, node.documentationComment);
    super.visitDeclaration(node);
  }
}

/// Check the files given as arguments.
///
/// Parameters:
/// - [paths]: Dart files to check.
///
/// Errors: exits with status 1 when a declaration is undocumented or a
/// file does not parse. Side Effects: reads the files; prints findings.
/// Complexity: O(n) in the source size. Thread Safety: call once.
/// Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `dart run tool/doc_coverage.dart lib/src/api.dart`.
///
/// See Also: [_Collector].
void main(List<String> paths) {
  var checked = 0;
  var missing = 0;
  for (final path in paths) {
    final result = parseFile(
      path: File(path).absolute.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    );
    final collector = _Collector(result.unit);
    result.unit.accept(collector);
    checked += collector.checked;
    missing += collector.missing.length;
    for (final finding in collector.missing) {
      stdout.writeln('$path:$finding: undocumented');
    }
  }
  stdout.writeln(
    'doc-coverage: ${checked - missing}/$checked declarations documented',
  );
  if (missing > 0) {
    exitCode = 1;
  }
}
