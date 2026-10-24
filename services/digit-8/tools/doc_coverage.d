// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          tools/doc_coverage.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Documentation coverage gate of the doc-coverage stage:
//                  every module and every declaration, private ones
//                  included, must carry a ddoc comment (CLAUDE.md 6.5.4).
// Related Docs:    services/digit-8/Dockerfile, CLAUDE.md 6.5.3 and 6.5.4,
//                  ADR-0030

/**
 * Documentation coverage gate of the digit-8 service.
 *
 * Description: reads the JSON description that `ldc2 -D -X` writes for
 * the service's sources (the compiler fills the `comment` field of a
 * declaration from its ddoc comment only when `-D` is given) and requires
 * a non-empty comment on every module and on every declaration at any
 * depth: functions, constructors, variables, constants, aliases, types
 * and enum members, whatever their protection. Imports, unittest blocks
 * and the `_d_cmain` mixin the compiler adds for `main` are not
 * declarations of the service and are skipped. A `ditto` comment counts
 * as documentation.
 *
 * Usage: `ldc2 -run tools/doc_coverage.d <description.json>`; the exit
 * status is 1 when an item is undocumented.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module doc_coverage;

import std.algorithm.searching : canFind, startsWith;
import std.file : readText;
import std.format : format;
import std.json : JSONType, JSONValue, parseJSON;
import std.stdio : stderr, writefln, writeln;
import std.string : strip;

/// Kinds of entries that are not declarations of the service.
private immutable string[] skippedKinds = ["import", "static import"];

/**
 * The counts of one check.
 *
 * Thread_Safety: a value type. Owner: AEC. Since: digit-8 0.1.0.
 */
struct Coverage
{
    /// Items that need a comment.
    size_t total;
    /// Items without one, as `file:line: kind name`.
    string[] missing;
}

/**
 * Whether an entry of the description is exempt from the check.
 *
 * Params:
 *   kind = the `kind` field.
 *   name = the `name` field.
 * Returns: true for imports, unittest blocks and the compiler's `main`
 * mixin.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
bool exempt(string kind, string name) pure @safe
{
    return skippedKinds.canFind(kind) || name.startsWith("__unittest")
        || (kind == "mixin" && name.startsWith("_d_cmain"));
}

///
unittest
{
    assert(exempt("import", "std.stdio"));
    assert(exempt("function", "__unittest_L12_C1"));
    assert(exempt("mixin", "_d_cmain!()"));
    assert(!exempt("function", "run"));
    assert(!exempt("mixin", "Something!()"));
}

/**
 * The text of a string field, or a fallback when the field is absent.
 *
 * Params:
 *   entry = a JSON object of the description.
 *   key = the field name.
 *   fallback = the value when the field is absent or not a string.
 * Returns: the text.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
string field(JSONValue entry, string key, string fallback = "") @safe
{
    auto value = key in entry.objectNoRef;
    return value is null || value.type != JSONType.string ? fallback : value.str;
}

///
unittest
{
    auto entry = parseJSON(`{"name":"x","line":3}`);
    assert(field(entry, "name") == "x");
    assert(field(entry, "line", "?") == "?");
}

/**
 * Check the members of one entry, recursively.
 *
 * Params:
 *   entry = a module, type or other entry with an optional `members`.
 *   file = the source file of the module the entry belongs to.
 *   coverage = receives the counts.
 *
 * Errors: none. Side Effects: none. Complexity: O(n) in the members.
 * Thread Safety: one thread. Owner: AEC. Since: digit-8 0.1.0.
 */
void checkMembers(JSONValue entry, string file, ref Coverage coverage) @safe
{
    auto members = "members" in entry.objectNoRef;
    if (members is null)
    {
        return;
    }
    foreach (member; members.arrayNoRef)
    {
        auto kind = field(member, "kind");
        auto name = field(member, "name");
        if (exempt(kind, name))
        {
            continue;
        }
        coverage.total++;
        if (field(member, "comment").strip.length == 0)
        {
            auto line = "line" in member.objectNoRef;
            coverage.missing ~= format!"%s:%s: %s %s"(file, line is null
                    ? "?" : line.toString, kind, name);
        }
        checkMembers(member, file, coverage);
    }
}

/**
 * Check every module of a description.
 *
 * Params:
 *   description = the parsed output of `ldc2 -X`: an array of modules.
 * Returns: the counts.
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: one
 * thread. Owner: AEC. Since: digit-8 0.1.0.
 */
Coverage check(JSONValue description) @safe
{
    Coverage coverage;
    foreach (module_; description.arrayNoRef)
    {
        auto file = field(module_, "file", "?");
        coverage.total++;
        if (field(module_, "comment").strip.length == 0)
        {
            coverage.missing ~= format!"%s: module %s"(file, field(module_, "name"));
        }
        checkMembers(module_, file, coverage);
    }
    return coverage;
}

///
unittest
{
    auto description = parseJSON(`[{"name":"m","kind":"module","file":"m.d","comment":"M.\n",
        "members":[{"name":"f","kind":"function","line":4,"comment":"F.\n"},
        {"name":"S","kind":"struct","line":6,"comment":"S.\n",
         "members":[{"name":"x","kind":"variable","line":8}]},
        {"name":"std.stdio","kind":"import","line":2},
        {"name":"__unittest_L9_C1","kind":"function","line":9,"comment":"\n"}]}]`);
    auto coverage = check(description);
    assert(coverage.total == 4);
    assert(coverage.missing == ["m.d:8: variable x"]);
}

/**
 * Run the gate.
 *
 * Params:
 *   args = the program name and the path of the JSON description.
 * Returns: 0 when every item is documented, 1 otherwise or on a usage
 * error.
 *
 * Errors: an unreadable or invalid description ends the program with an
 * exception (status 1). Side Effects: reads the file; prints the result.
 * Complexity: O(n). Thread Safety: the main thread. Owner: AEC.
 * Since: digit-8 0.1.0.
 */
int main(string[] args)
{
    if (args.length != 2)
    {
        stderr.writeln("usage: doc_coverage <description.json>");
        return 1;
    }
    auto description = parseJSON(readText(args[1]));
    auto coverage = check(description);
    foreach (item; coverage.missing)
    {
        writeln("undocumented: ", item);
    }
    auto documented = coverage.total - coverage.missing.length;
    writefln!"doc-coverage: %d/%d items documented in %d files"(documented,
            coverage.total, description.arrayNoRef.length);
    return coverage.missing.length == 0 ? 0 : 1;
}
