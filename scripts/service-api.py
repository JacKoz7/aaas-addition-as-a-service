# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/service-api.py
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Generates the events section of every service API.md from
#                  the topic registry and the event schemas, and the gRPC
#                  section from contracts/proto, and checks that the
#                  committed sections are up to date (--check).
# Related Docs:    ADR-0013, ADR-0020, CLAUDE.md (6.5.5, API.md "generated"),
#                  contracts/events/README.md, contracts/proto/README.md,
#                  Makefile (api-md, contracts-check)
"""Service API reference generator (command-line tool).

Summary:
    Renders the events and the gRPC contract of each service into its API.md.

Description:
    ``CLAUDE.md`` 6.5.5 requires ``docs/API.md`` of every service to be
    generated, not edited by hand. This tool owns the part derived from the
    event contracts: in every ``services/*/docs/API.md`` and
    ``frontend/*/docs/API.md`` that contains the markers
    ``<!-- BEGIN GENERATED: events -->`` and ``<!-- END GENERATED: events -->``,
    the text between them is replaced by:

    - the topics whose producer (``contracts/events/topics.psv``) is the
      component, with partitions, message key, schema link and payload fields;
    - the topics whose consumers list the component, with the same details.

    In every API.md that contains ``<!-- BEGIN GENERATED: grpc -->`` and
    ``<!-- END GENERATED: grpc -->``, the text between them is replaced by
    the gRPC contract of the component: the services, RPCs and messages of
    ``contracts/proto/aaas/<package>/v1/*.proto``, where ``<package>`` is
    the component name with ``-`` replaced by ``_`` (ADR-0020), with the
    leading comments of the proto file as descriptions.

    The component name is the directory name. Without ``--check`` the files
    are rewritten; with ``--check`` nothing is written and the exit code is 1
    when a section differs from what would be generated. The HTTP section
    stays hand-maintained until its contracts exist (OpenAPI P2.2).

Business Justification:
    A service's published contract must match the registry that creates the
    topics and the schemas that validate the events; generating the section
    makes drift impossible to commit unnoticed.

Owner: Platform Enablement Guild (PEG)
Since: service-api 0.1.0
Versions: 0.1.0 (P1.4) events section; 0.2.0 (P2.1) gRPC section.
See Also: scripts/validate-events.py, scripts/docs-portal.py, ADR-0013.
"""

from __future__ import annotations

import json
import re
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

#: Marker opening the generated events section.
BEGIN = "<!-- BEGIN GENERATED: events (scripts/service-api.py, do not edit) -->"

#: Marker closing the generated events section.
END = "<!-- END GENERATED: events -->"

#: Marker opening the generated gRPC section.
GRPC_BEGIN = "<!-- BEGIN GENERATED: grpc (scripts/service-api.py, do not edit) -->"

#: Marker closing the generated gRPC section.
GRPC_END = "<!-- END GENERATED: grpc -->"

#: One ``rpc Name(Request) returns (Response);`` line of a proto file.
RPC_RE = re.compile(r"^\s*rpc\s+(\w+)\s*\(\s*(\w+)\s*\)\s*returns\s*\(\s*(\w+)\s*\)")

#: One scalar or message field line: optional ``repeated``, type, name, number.
FIELD_RE = re.compile(r"^\s*(repeated\s+)?([\w.]+)\s+(\w+)\s*=\s*(\d+)\s*;")


def read_registry(root: Path) -> list[list[str]]:
    """Read the topic registry.

    Summary:
        Returns the rows of ``contracts/events/topics.psv``.

    Description:
        Blank lines and ``#`` comments are skipped; each row is split into
        its five columns ``topic|partitions|producer|consumers|purpose``.

    Business Justification:
        The registry names the producer and consumers of every topic.

    Parameters:
        root (Path): repository root.

    Returns:
        list[list[str]]: one row of five strings per topic, in file order.

    Errors:
        OSError: the registry cannot be read.
        ValueError: a row does not have five columns.

    Side Effects:
        Reads one file.

    Complexity: O(n) time and memory in the number of rows.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> read_registry(Path(__file__).resolve().parent.parent)[0][0]
        'aaas.key.pressed.v1'

    See Also: consumers_of.
    """
    rows = []
    for line in (root / "contracts" / "events" / "topics.psv").read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        columns = line.split("|")
        if len(columns) != 5:
            raise ValueError(f"topics.psv: expected 5 columns: {line}")
        rows.append(columns)
    return rows


def consumers_of(row: list[str]) -> list[str]:
    """Extract the consuming components of a registry row.

    Summary:
        Splits the consumers column into component names.

    Description:
        The column lists names separated by commas; text in parentheses (for
        example ``(audit)`` or a step note) is not a component and is removed.

    Business Justification:
        Lets the generator find the topics a component consumes.

    Parameters:
        row (list[str]): registry row.

    Returns:
        list[str]: component names, possibly empty.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) in the column length.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> consumers_of(["t", "3", "p", "parser, stopwatch (from P8.16)", "x"])
        ['parser', 'stopwatch']
        >>> consumers_of(["t", "3", "p", "(audit)", "x"])
        []

    See Also: read_registry.
    """
    text, depth, kept = row[3], 0, []
    for char in text:
        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(0, depth - 1)
        elif depth == 0:
            kept.append(char)
    return [name.strip() for name in "".join(kept).split(",") if name.strip()]


def field_rows(schema: dict[str, Any]) -> list[str]:
    """Render the payload fields of an event schema as table rows.

    Summary:
        One Markdown row per payload property: name, required, description.

    Description:
        Reads ``properties.payload`` of the event schema. Pipes in
        descriptions are escaped; descriptions are kept verbatim otherwise.

    Business Justification:
        Every field of every event is documented in the service reference.

    Parameters:
        schema (dict[str, Any]): parsed event schema.

    Returns:
        list[str]: Markdown table rows.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) in the number of fields.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> s = {"properties": {"payload": {"required": ["a"], "properties": {"a": {"description": "x|y"}}}}}
        >>> field_rows(s)
        ['| `a` | yes | x\\\\|y |']

    See Also: render_topic.
    """
    payload = schema.get("properties", {}).get("payload", {})
    required = set(payload.get("required", []))
    rows = []
    for name, node in payload.get("properties", {}).items():
        description = str(node.get("description", "—")).replace("|", "\\|")
        rows.append(f"| `{name}` | {'yes' if name in required else 'no'} | {description} |")
    return rows


def render_topic(root: Path, row: list[str], direction: str) -> str:
    """Render one topic of a component.

    Summary:
        Markdown subsection for one produced or consumed topic.

    Description:
        Shows the purpose, partitions, message key, the schema link (or a
        note that the schema does not exist yet) and the payload fields. The
        key is ``sessionId`` for an event whose schema fixes ``taskId`` to
        null and ``taskId`` otherwise (CLAUDE.md 4.2, ADR-0013).

    Business Justification:
        The service reference shows exactly what goes over the bus.

    Parameters:
        root (Path): repository root.
        row (list[str]): registry row of the topic.
        direction (str): ``produced`` or ``consumed``.

    Returns:
        str: Markdown text ending with a blank line.

    Errors:
        OSError: a schema exists but cannot be read.
        ValueError: a schema is not valid JSON.

    Side Effects:
        Reads one schema file.

    Complexity: O(schema size).
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> row = read_registry(Path(__file__).resolve().parent.parent)[0]
        >>> render_topic(Path(__file__).resolve().parent.parent, row, "produced").splitlines()[0]
        '### `aaas.key.pressed.v1` (produced)'

    See Also: render_section, field_rows.
    """
    topic, partitions, producer, _, purpose = row
    path = root / "contracts" / "events" / f"{topic}.schema.json"
    schema = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    # Events without a task (taskId fixed to null) are keyed by session (ADR-0013).
    without_task = schema.get("properties", {}).get("taskId", {}).get("type") == "null"
    key = "`sessionId`" if without_task else "`taskId`"
    text = f"### `{topic}` ({direction})\n\n{purpose}\n\n"
    text += f"- Producer: `{producer}`; partitions: {partitions}; message key: {key}.\n"
    if not schema:
        return text + "- Schema: not defined yet (added by the step that introduces the event).\n\n"
    text += f"- Schema: [`{path.name}`](../../../contracts/events/{path.name}) (`{schema.get('$id', '')}`), "
    text += "in the envelope of `CLAUDE.md` 4.2.\n\n"
    text += "| Payload field | Required | Description |\n| --- | --- | --- |\n"
    return text + "\n".join(field_rows(schema)) + "\n\n"


def render_section(root: Path, component: str) -> str:
    """Render the generated events section of a component.

    Summary:
        Produced topics, then consumed topics, or a statement that there are none.

    Description:
        The text placed between the markers, without the markers.

    Business Justification:
        See the module documentation.

    Parameters:
        root (Path): repository root.
        component (str): component name (directory name).

    Returns:
        str: Markdown text.

    Errors:
        OSError, ValueError: as read_registry and render_topic.

    Side Effects:
        Reads the registry and schemas.

    Complexity: O(registry size + schema sizes).
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> "neither produces nor consumes" in render_section(Path(__file__).resolve().parent.parent, "gateway")
        True

    See Also: update.
    """
    rows = read_registry(root)
    produced = [r for r in rows if r[2] == component]
    consumed = [r for r in rows if component in consumers_of(r)]
    if not produced and not consumed:
        return f"\n`{component}` neither produces nor consumes events.\n\n"
    text = "\n"
    text += "".join(render_topic(root, r, "produced") for r in produced)
    text += "".join(render_topic(root, r, "consumed") for r in consumed)
    return text


def parse_proto(text: str) -> dict[str, Any]:
    """Extract the package, services and messages of a proto file.

    Summary:
        Minimal parser for the uniform proto files of ``contracts/proto``.

    Description:
        Reads the file line by line. A run of ``//`` comment lines directly
        above a definition (no blank line in between) becomes its
        description; the file header is separated by a blank line and is
        therefore ignored. Recognised definitions: ``package``, top-level
        ``service`` with its ``rpc`` lines, top-level ``message`` with its
        fields. Nested messages, enums, oneofs and options are not used by
        the contracts and are not recognised; ``buf lint`` guarantees the
        layout the parser relies on.

    Business Justification:
        The gRPC section of API.md is derived from the contract itself, so
        the reference cannot drift from it (ADR-0020).

    Parameters:
        text (str): content of a ``.proto`` file.

    Returns:
        dict[str, Any]: ``package`` (str), ``services`` (list of dicts with
        ``name``, ``doc``, ``rpcs``: list of ``name``, ``request``,
        ``response``, ``doc``) and ``messages`` (dict from name to a dict
        with ``doc`` and ``fields``: list of ``name``, ``number``, ``type``,
        ``doc``).

    Errors:
        None (unrecognised lines are skipped).

    Side Effects:
        None.

    Complexity: O(n) time and memory in the number of lines.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.2.0

    Example:
        >>> p = parse_proto("package a.v1;\\n// S.\\nservice S {\\n  // R.\\n  rpc R(Q) returns (A);\\n}\\n")
        >>> p["package"], p["services"][0]["rpcs"][0]["doc"]
        ('a.v1', 'R.')

    See Also: render_grpc, contracts/proto/README.md.
    """
    result: dict[str, Any] = {"package": "", "services": [], "messages": {}}
    comment: list[str] = []
    service: dict[str, Any] | None = None
    message: dict[str, Any] | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("//"):
            comment.append(line[2:].strip())
            continue
        doc = " ".join(part for part in comment if part)
        comment = []
        if not line:
            continue
        if line.startswith("package "):
            result["package"] = line[len("package ") :].rstrip(";").strip()
        elif raw.startswith("service "):
            service = {"name": line.split()[1], "doc": doc, "rpcs": []}
            result["services"].append(service)
        elif raw.startswith("message "):
            message = {"doc": doc, "fields": []}
            result["messages"][line.split()[1]] = message
        elif raw.startswith("}"):
            service, message = None, None
        elif service is not None and (m := RPC_RE.match(raw)):
            service["rpcs"].append({"name": m[1], "request": m[2], "response": m[3], "doc": doc})
        elif message is not None and (m := FIELD_RE.match(raw)):
            kind = f"repeated {m[2]}" if m[1] else m[2]
            message["fields"].append({"name": m[3], "number": int(m[4]), "type": kind, "doc": doc})
    return result


def render_grpc(root: Path, component: str) -> str:
    """Render the generated gRPC section of a component.

    Summary:
        Services, RPCs and messages of the component's proto package.

    Description:
        Looks for ``contracts/proto/aaas/<component with _>/v1/*.proto``.
        Without such files the section states that the component serves no
        gRPC contract. Otherwise, per service: its description, a table of
        RPCs (request, response, description) and one field table per
        request and response message. Whether the contract is already
        served is stated by the hand-written text around the section.

    Business Justification:
        See :func:`parse_proto`.

    Parameters:
        root (Path): repository root.
        component (str): component name (directory name).

    Returns:
        str: Markdown text starting and ending with a blank line.

    Errors:
        OSError: a proto file cannot be read.

    Side Effects:
        Reads proto files.

    Complexity: O(total size of the component's proto files).
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.2.0

    Example:
        >>> root = Path(__file__).resolve().parent.parent
        >>> "serves no gRPC contract" in render_grpc(root, "gateway")
        True
        >>> "`Next`" in render_grpc(root, "successor")
        True

    See Also: parse_proto, update.
    """
    package_dir = root / "contracts" / "proto" / "aaas" / component.replace("-", "_") / "v1"
    protos = sorted(package_dir.glob("*.proto")) if package_dir.is_dir() else []
    if not protos:
        return f"\n`{component}` serves no gRPC contract of `contracts/proto`.\n\n"
    text = "\n"
    for proto in protos:
        parsed = parse_proto(proto.read_text(encoding="utf-8"))
        rel = proto.relative_to(root).as_posix()
        for service in parsed["services"]:
            text += f"### `{parsed['package']}.{service['name']}`\n\n{service['doc']}\n\n"
            text += f"- Contract: [`{proto.name}`](../../../{rel}), package `{parsed['package']}`.\n\n"
            text += "| RPC | Request | Response | Description |\n| --- | --- | --- | --- |\n"
            for rpc in service["rpcs"]:
                text += f"| `{rpc['name']}` | `{rpc['request']}` | `{rpc['response']}` | {escape(rpc['doc'])} |\n"
            text += "\n"
            for rpc in service["rpcs"]:
                for name in (rpc["request"], rpc["response"]):
                    message = parsed["messages"].get(name, {"doc": "", "fields": []})
                    text += f"#### `{name}`\n\n{message['doc']}\n\n"
                    if not message["fields"]:
                        text += "No fields.\n\n"
                        continue
                    text += "| Field | Number | Type | Description |\n| --- | --- | --- | --- |\n"
                    for field in message["fields"]:
                        text += (
                            f"| `{field['name']}` | {field['number']} | `{field['type']}` | {escape(field['doc'])} |\n"
                        )
                    text += "\n"
    return text


def escape(cell: str) -> str:
    """Make text safe for a Markdown table cell.

    Summary:
        Escapes the column separator ``|``.

    Description:
        Proto comments are plain text; only ``|`` would break a table row.

    Business Justification:
        Keeps the generated tables well-formed.

    Parameters:
        cell (str): cell text.

    Returns:
        str: the text with ``|`` escaped.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) in the length of the text.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.2.0

    Example:
        >>> escape("a | b")
        'a \\\\| b'

    See Also: render_grpc.
    """
    return cell.replace("|", "\\|")


def update(root: Path, check: bool) -> list[str]:
    """Regenerate (or check) the generated sections of every component API.md.

    Summary:
        Applies render_section (events) and render_grpc (gRPC) to every
        API.md with the corresponding markers.

    Description:
        A section whose two markers are not both present is skipped. In
        check mode nothing is written.

    Business Justification:
        One command for ``make api-md`` and one for ``make contracts-check``.

    Parameters:
        root (Path): repository root.
        check (bool): report differences instead of writing.

    Returns:
        list[str]: repository-relative paths that were (or would be) changed.

    Errors:
        OSError, ValueError: as render_section; ValueError also when the END
        marker precedes the BEGIN marker.

    Side Effects:
        Reads every component API.md; writes the changed ones unless ``check``.

    Complexity: O(total size of the files).
    Thread Safety: not safe (writes files).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> update(Path(__file__).resolve().parent.parent, check=True)
        []

    See Also: main.
    """
    sections: list[tuple[str, str, Callable[[Path, str], str]]] = [
        (BEGIN, END, render_section),
        (GRPC_BEGIN, GRPC_END, render_grpc),
    ]
    changed = []
    for api in sorted([*root.glob("services/*/docs/API.md"), *root.glob("frontend/*/docs/API.md")]):
        text = api.read_text(encoding="utf-8")
        updated = text
        for begin, end_marker, render in sections:
            if begin not in updated or end_marker not in updated:
                continue
            start, end = updated.index(begin) + len(begin), updated.index(end_marker)
            if end < start:
                raise ValueError(f"{api}: the END marker precedes the BEGIN marker")
            updated = updated[:start] + render(root, api.parent.parent.name) + updated[end:]
        if updated != text:
            changed.append(api.relative_to(root).as_posix())
            if not check:
                api.write_text(updated, encoding="utf-8")
    return changed


def main(argv: list[str]) -> int:
    """Run the generator from the command line.

    Summary:
        ``service-api.py [--check]``.

    Description:
        Prints the changed (or stale) files; in check mode returns 1 when any
        file is stale.

    Business Justification:
        Clear exit codes for CI and developers.

    Parameters:
        argv (list[str]): command-line arguments without the program name.

    Returns:
        int: 0 on success, 1 when ``--check`` finds stale files, 2 on usage errors.

    Errors:
        OSError, ValueError: propagated from update.

    Side Effects:
        As update; writes to stdout and stderr.

    Complexity: as update.
    Thread Safety: not applicable (process entry point).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> import contextlib, io
        >>> with contextlib.redirect_stdout(io.StringIO()):
        ...     code = main(["--check"])
        >>> code
        0

    See Also: update.
    """
    if argv not in ([], ["--check"]):
        print("usage: service-api.py [--check]", file=sys.stderr)
        return 2
    check = argv == ["--check"]
    print("==> generated events and gRPC sections of API.md" + (" (check)" if check else ""))
    changed = update(Path(__file__).resolve().parent.parent, check)
    for path in changed:
        print(f"    {'stale' if check else 'updated'}: {path}", file=sys.stderr if check else sys.stdout)
    if check and changed:
        print("error: run `make api-md` and commit the result", file=sys.stderr)
        return 1
    print("    up to date" if not changed else f"    {len(changed)} file(s) updated")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
