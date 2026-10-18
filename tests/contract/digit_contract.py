# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          tests/contract/digit_contract.py
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Black-box contract test of one running digit service
#                  against contracts/http/digit.yaml: status codes, media
#                  types, response schemas taken from the OpenAPI document,
#                  the arithmetic of the digit, metrics and error format.
# Related Docs:    contracts/http/digit.yaml, tests/contract/README.md,
#                  tests/contract/digit.sh, ADR-0021, CLAUDE.md 4.4
"""Digit service contract test (command-line tool).

Summary:
    Checks that one running digit service fulfils ``contracts/http/digit.yaml``.

Description:
    ``digit_contract.py <digit> <base-url>`` sends real HTTP requests to the
    service and checks every rule of the contract that is observable from
    outside. Response bodies are validated against the schemas of the
    OpenAPI document itself (JSON Schema 2020-12, the dialect of OpenAPI
    3.1), so the test cannot drift from the contract. Every check prints one
    ``ok``/``not ok`` line (TAP style); the exit code is 0 when all passed.

    That the digit is read from the service's own SQLite database and not
    hard-coded (``CLAUDE.md`` 4.4) is not observable over HTTP; it is
    verified by the unit tests and the review of each digit service.

Business Justification:
    Ten digit services in ten languages must be interchangeable for the
    successor and carry services; one shared test is the only way to prove
    that they all speak the same contract.

Owner: Arithmetic Excellence Center (AEC)
Since: contract-tests 0.1.0
See Also: tests/contract/digit.sh, tests/contract/stub/digit_stub.py.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.request
from collections.abc import Callable
from functools import partial
from pathlib import Path
from typing import Any

import jsonschema
import yaml

#: OpenAPI document of the digit services, relative to the repository root.
CONTRACT = Path(__file__).resolve().parent.parent.parent / "contracts" / "http" / "digit.yaml"

#: Seconds before a request is abandoned (CLAUDE.md 6.1: 2 s per call).
TIMEOUT = 2.0

#: A valid W3C traceparent sent to check that the header is accepted.
TRACEPARENT = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"


class Response:
    """An HTTP response reduced to what the checks need.

    Summary:
        Status, headers (lower-case names) and body text.

    Description:
        Built by :func:`request` for 2xx as well as error statuses, so that
        the checks treat both alike.

    Business Justification:
        Keeps the checks independent of urllib's exception-based errors.

    Parameters:
        status (int): HTTP status code.
        headers (dict[str, str]): response headers, names in lower case.
        body (str): response body decoded as UTF-8.

    Returns:
        Not applicable (class).

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(1).
    Thread Safety: immutable after construction; safe.
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        >>> Response(200, {"content-type": "application/json"}, "{}").media_type()
        'application/json'

    See Also: request.
    """

    def __init__(self, status: int, headers: dict[str, str], body: str) -> None:
        """Store the parts of the response.

        Summary:
            Constructor.

        Description:
            Stores the arguments unchanged.

        Business Justification:
            See the class documentation.

        Parameters:
            status (int): HTTP status code.
            headers (dict[str, str]): headers with lower-case names.
            body (str): decoded body.

        Returns:
            None.

        Errors:
            None.

        Side Effects:
            None.

        Complexity: O(1).
        Thread Safety: not applicable (construction).
        Owner: Arithmetic Excellence Center (AEC)
        Since: contract-tests 0.1.0

        Example:
            >>> Response(404, {}, "").status
            404

        See Also: Response.media_type.
        """
        self.status = status
        self.headers = headers
        self.body = body

    def media_type(self) -> str:
        """Return the media type of the response without parameters.

        Summary:
            ``Content-Type`` without ``; charset=…``, lower case.

        Description:
            Empty string when the header is absent.

        Business Justification:
            The contract fixes media types, not their parameters.

        Parameters:
            None.

        Returns:
            str: media type, for example ``application/json``.

        Errors:
            None.

        Side Effects:
            None.

        Complexity: O(n) in the header length.
        Thread Safety: safe (read-only).
        Owner: Arithmetic Excellence Center (AEC)
        Since: contract-tests 0.1.0

        Example:
            >>> Response(200, {"content-type": "Text/Plain; version=0.0.4"}, "").media_type()
            'text/plain'

        See Also: Response.
        """
        return self.headers.get("content-type", "").split(";")[0].strip().lower()

    def json(self) -> Any:
        """Parse the body as JSON.

        Summary:
            ``json.loads`` of the body.

        Description:
            Raises when the body is not JSON; the checks report that as a
            failure.

        Business Justification:
            Every JSON operation of the contract is checked through this.

        Parameters:
            None.

        Returns:
            Any: the decoded document.

        Errors:
            json.JSONDecodeError: the body is not valid JSON.

        Side Effects:
            None.

        Complexity: O(n) in the body length.
        Thread Safety: safe (read-only).
        Owner: Arithmetic Excellence Center (AEC)
        Since: contract-tests 0.1.0

        Example:
            >>> Response(200, {}, '{"digit": 7}').json()
            {'digit': 7}

        See Also: Response.
        """
        return json.loads(self.body)


def request(base_url: str, method: str, path: str, headers: dict[str, str] | None = None) -> Response:
    """Send one HTTP request and return the response, whatever its status.

    Summary:
        urllib request with the contract test's timeout.

    Description:
        HTTP error statuses (4xx, 5xx) are returned as responses, not
        raised. Connection errors and timeouts propagate.

    Business Justification:
        The checks need error responses as data (404, 405 problems).

    Parameters:
        base_url (str): for example ``http://digit-7:8080`` (no trailing slash).
        method (str): HTTP method.
        path (str): absolute path, for example ``/next``.
        headers (dict[str, str] | None): extra request headers.

    Returns:
        Response: the response.

    Errors:
        urllib.error.URLError, TimeoutError: the service did not answer.

    Side Effects:
        One network request.

    Complexity: O(n) in the response size.
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        Requires a running service: ``request("http://digit-7:8080", "GET", "/value")``.

    See Also: Response.
    """
    req = urllib.request.Request(base_url + path, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw, status, hdrs = resp.read(), resp.status, resp.headers
    except urllib.error.HTTPError as err:
        raw, status, hdrs = err.read(), err.code, err.headers
    return Response(status, {k.lower(): v for k, v in hdrs.items()}, raw.decode("utf-8", "replace"))


def load_contract(path: Path = CONTRACT) -> dict[str, Any]:
    """Load the OpenAPI document of the digit services.

    Summary:
        YAML of ``contracts/http/digit.yaml`` as a dict.

    Description:
        Read once per run; the schemas used by the checks come from it.

    Business Justification:
        The contract file is the single source of the expected shapes.

    Parameters:
        path (Path): location of the document.

    Returns:
        dict[str, Any]: the parsed document.

    Errors:
        OSError: the file cannot be read.
        yaml.YAMLError: the file is not valid YAML.

    Side Effects:
        Reads one file.

    Complexity: O(n) in the file size.
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        >>> load_contract()["openapi"]
        '3.1.0'

    See Also: schema_errors.
    """
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def schema_errors(contract: dict[str, Any], name: str, document: Any) -> list[str]:
    """Validate a document against a component schema of the contract.

    Summary:
        JSON Schema 2020-12 validation of ``#/components/schemas/<name>``.

    Description:
        The schema is a ``$ref`` to the component, embedded next to a copy
        of ``components`` so that every reference of the contract resolves
        inside the same document.

    Business Justification:
        Response shapes are checked by the contract's own schemas.

    Parameters:
        contract (dict[str, Any]): the OpenAPI document.
        name (str): component schema name, for example ``DigitNext``.
        document (Any): the decoded response body.

    Returns:
        list[str]: one message per violation; empty when valid.

    Errors:
        KeyError: no component schema has this name.

    Side Effects:
        None.

    Complexity: O(n) in the document size.
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        >>> c = load_contract()
        >>> schema_errors(c, "DigitNext", {"digit": 9, "next": 0, "carry": True})
        []
        >>> len(schema_errors(c, "DigitNext", {"digit": 9, "next": 10}))
        2

    See Also: load_contract.
    """
    contract["components"]["schemas"][name]  # noqa: B018 - fail early on an unknown name
    schema = {"$ref": f"#/components/schemas/{name}", "components": contract["components"]}
    validator = jsonschema.Draft202012Validator(schema)
    return [f"{'/'.join(map(str, e.absolute_path)) or '(root)'}: {e.message}" for e in validator.iter_errors(document)]


def metric_value(text: str, name: str, labels: dict[str, str]) -> float | None:
    """Find the value of one Prometheus sample.

    Summary:
        Value of the sample of ``name`` whose labels include ``labels``.

    Description:
        Parses the text exposition format line by line; label order and
        extra labels do not matter. Returns the first matching sample.

    Business Justification:
        The contract fixes the counter ``digit_requests_total``.

    Parameters:
        text (str): metrics exposition.
        name (str): metric name.
        labels (dict[str, str]): labels that must be present with these values.

    Returns:
        float | None: the value, or None when no sample matches.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) in the text size.
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        >>> metric_value('m{a="1",b="x"} 3', "m", {"b": "x"})
        3.0
        >>> metric_value('m{a="1"} 3', "m", {"a": "2"}) is None
        True

    See Also: check_metrics.
    """
    pattern = re.compile(rf"^{re.escape(name)}(?:\{{(.*)\}})?\s+(\S+)")
    for line in text.splitlines():
        match = pattern.match(line)
        if not match:
            continue
        found = dict(re.findall(r'(\w+)="((?:[^"\\]|\\.)*)"', match[1] or ""))
        if all(found.get(k) == v for k, v in labels.items()):
            return float(match[2])
    return None


def check_json(
    base: str,
    contract: dict[str, Any],
    path: str,
    schema: str,
    expected: dict[str, Any],
    headers: dict[str, str] | None = None,
) -> list[str]:
    """Check a JSON operation: status, media type, schema and values.

    Summary:
        ``GET <path>`` must answer 200 ``application/json`` that matches
        ``schema`` and has the ``expected`` field values.

    Description:
        Stops at the first structural failure (status, media type) because
        the body is meaningless then; otherwise reports every schema
        violation and every unexpected value.

    Business Justification:
        ``/value`` and ``/next`` are the arithmetic of the digit.

    Parameters:
        base (str): service URL.
        contract (dict[str, Any]): the OpenAPI document.
        path (str): operation path.
        schema (str): component schema name.
        expected (dict[str, Any]): field values the body must have.
        headers (dict[str, str] | None): extra request headers.

    Returns:
        list[str]: failures; empty when the check passed.

    Errors:
        As :func:`request`; json.JSONDecodeError for a non-JSON body.

    Side Effects:
        One request.

    Complexity: O(n) in the response size.
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        Requires a running service; see :func:`checks`.

    See Also: checks, schema_errors.
    """
    resp = request(base, "GET", path, headers)
    if resp.status != 200:
        return [f"status {resp.status}, expected 200"]
    if resp.media_type() != "application/json":
        return [f"content type {resp.media_type()!r}, expected 'application/json'"]
    body = resp.json()
    errors = schema_errors(contract, schema, body)
    errors += [f"{k} = {body.get(k)!r}, expected {v!r}" for k, v in expected.items() if body.get(k) != v]
    return errors


def check_repeatable(base: str, contract: dict[str, Any]) -> list[str]:
    """Check that ``GET /next`` answers the same body three times.

    Summary:
        The operation is safe and idempotent.

    Description:
        Compares the raw bodies of three consecutive calls.

    Business Justification:
        Callers retry ``/next`` freely (contract description); a digit
        whose answer changes between calls would corrupt the Peano loop.

    Parameters:
        base (str): service URL.
        contract (dict[str, Any]): the OpenAPI document (unused; uniform
            signature).

    Returns:
        list[str]: failures; empty when the check passed.

    Errors:
        As :func:`request`.

    Side Effects:
        Three requests.

    Complexity: O(n) in the response size.
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        Requires a running service; see :func:`checks`.

    See Also: checks.
    """
    bodies = [request(base, "GET", "/next").body for _ in range(3)]
    return [] if len(set(bodies)) == 1 else [f"answers differ: {bodies}"]


def check_health(base: str, contract: dict[str, Any]) -> list[str]:
    """Check ``GET /health``: 200, ``Health`` schema, status and database ok.

    Summary:
        The service reports itself healthy with a database check.

    Description:
        A digit service checks only its SQLite database (``checks.database``).

    Business Justification:
        Compose (and from P5.1 Consul) relies on this endpoint.

    Parameters:
        base (str): service URL.
        contract (dict[str, Any]): the OpenAPI document.

    Returns:
        list[str]: failures; empty when the check passed.

    Errors:
        As :func:`request`; json.JSONDecodeError for a non-JSON body.

    Side Effects:
        One request.

    Complexity: O(n) in the response size.
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        Requires a running service; see :func:`checks`.

    See Also: checks.
    """
    resp = request(base, "GET", "/health")
    if resp.status != 200 or resp.media_type() != "application/json":
        return [f"status {resp.status} ({resp.media_type()!r}), expected 200 application/json"]
    body = resp.json()
    errors = schema_errors(contract, "Health", body)
    if body.get("status") != "ok" or body.get("checks", {}).get("database") != "ok":
        errors.append(f"body {body}, expected status ok and checks.database ok")
    return errors


def check_metrics(base: str, contract: dict[str, Any], digit: int) -> list[str]:
    """Check ``GET /metrics`` for the counter ``digit_requests_total``.

    Summary:
        The counter exists and counted the earlier ``/value`` and ``/next``
        calls of this run.

    Description:
        Requires the ``# TYPE`` line and a sample >= 1 with the labels
        ``digit``, ``endpoint`` (``value`` and ``next``) and
        ``outcome="ok"``. Runs after the arithmetic checks, which made those
        calls.

    Business Justification:
        One dashboard covers all ten digit services (P7.3).

    Parameters:
        base (str): service URL.
        contract (dict[str, Any]): the OpenAPI document (unused; uniform
            signature).
        digit (int): the digit of the service.

    Returns:
        list[str]: failures; empty when the check passed.

    Errors:
        As :func:`request`.

    Side Effects:
        One request.

    Complexity: O(n) in the size of the exposition.
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        Requires a running service; see :func:`checks`.

    See Also: metric_value.
    """
    resp = request(base, "GET", "/metrics")
    if resp.status != 200 or resp.media_type() != "text/plain":
        return [f"status {resp.status} ({resp.media_type()!r}), expected 200 text/plain"]
    errors = []
    if not re.search(r"^# TYPE digit_requests_total counter$", resp.body, re.MULTILINE):
        errors.append("no '# TYPE digit_requests_total counter' line")
    for endpoint in ("value", "next"):
        labels = {"digit": str(digit), "endpoint": endpoint, "outcome": "ok"}
        value = metric_value(resp.body, "digit_requests_total", labels)
        if value is None or value < 1:
            errors.append(f"digit_requests_total{labels} is {value}, expected >= 1")
    return errors


def check_problem(
    base: str, contract: dict[str, Any], method: str, path: str, status: int, allow: bool = False
) -> list[str]:
    """Check an error answer: status, problem+json, ``Problem`` schema.

    Summary:
        ``<method> <path>`` must answer ``status`` as RFC 9457 problem details.

    Description:
        The problem's ``status`` member must equal the HTTP status; with
        ``allow``, the ``Allow`` header must list ``GET``.

    Business Justification:
        Every AaaS error is ``application/problem+json`` (``CLAUDE.md`` 4.1).

    Parameters:
        base (str): service URL.
        contract (dict[str, Any]): the OpenAPI document.
        method (str): HTTP method.
        path (str): request path.
        status (int): expected HTTP status.
        allow (bool): also check the ``Allow`` header (405).

    Returns:
        list[str]: failures; empty when the check passed.

    Errors:
        As :func:`request`; json.JSONDecodeError for a non-JSON body.

    Side Effects:
        One request.

    Complexity: O(n) in the response size.
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        Requires a running service; see :func:`checks`.

    See Also: checks.
    """
    resp = request(base, method, path)
    if resp.status != status:
        return [f"status {resp.status}, expected {status}"]
    if resp.media_type() != "application/problem+json":
        return [f"content type {resp.media_type()!r}, expected 'application/problem+json'"]
    body = resp.json()
    errors = schema_errors(contract, "Problem", body)
    if body.get("status") != status:
        errors.append(f"problem status {body.get('status')!r}, expected {status}")
    if allow and "GET" not in [m.strip() for m in resp.headers.get("allow", "").split(",")]:
        errors.append(f"Allow header {resp.headers.get('allow')!r} does not list GET")
    return errors


def checks(digit: int) -> list[tuple[str, Callable[[str, dict[str, Any]], list[str]]]]:
    """List the checks of the contract for one digit.

    Summary:
        Pairs of (description, check function).

    Description:
        A check function takes the base URL and the contract and returns
        the list of its failures (empty when it passed). The order matters:
        the metrics check relies on the earlier calls of ``/value`` and
        ``/next``.

    Business Justification:
        Every observable rule of ``contracts/http/digit.yaml`` is one line of
        the report.

    Parameters:
        digit (int): the digit the service must represent, 0..9.

    Returns:
        list[tuple[str, Callable]]: the checks in execution order.

    Errors:
        None.

    Side Effects:
        None (the returned functions perform requests).

    Complexity: O(1).
    Thread Safety: safe (no shared state).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        >>> [title for title, _ in checks(9)][1]
        "GET /next answers {'digit': 9, 'next': 0, 'carry': True}"

    See Also: run.
    """
    value = {"digit": digit, "value": digit}
    successor = {"digit": digit, "next": (digit + 1) % 10, "carry": digit == 9}
    trace = {"traceparent": TRACEPARENT}
    return [
        (f"GET /value answers {value}", partial(check_json, path="/value", schema="DigitValue", expected=value)),
        (f"GET /next answers {successor}", partial(check_json, path="/next", schema="DigitNext", expected=successor)),
        ("GET /next is repeatable (same body three times)", check_repeatable),
        (
            "GET /value accepts a traceparent header",
            partial(check_json, path="/value", schema="DigitValue", expected=value, headers=trace),
        ),
        ("GET /health answers ok with the database check", check_health),
        ("GET /metrics counts value and next in digit_requests_total", partial(check_metrics, digit=digit)),
        (
            "GET on an unknown path answers 404 problem+json",
            partial(check_problem, method="GET", path="/no-such-path", status=404),
        ),
        (
            "POST /value answers 405 problem+json with Allow: GET",
            partial(check_problem, method="POST", path="/value", status=405, allow=True),
        ),
    ]


def run(digit: int, base_url: str) -> int:
    """Run every check and print a TAP-style report.

    Summary:
        Executes :func:`checks` against one service.

    Description:
        A check that raises (connection refused, invalid JSON) counts as a
        failure with the exception as its message; the remaining checks
        still run.

    Business Justification:
        One readable report per digit service, in CI and locally.

    Parameters:
        digit (int): expected digit, 0..9.
        base_url (str): service URL without a trailing slash.

    Returns:
        int: 0 when every check passed, 1 otherwise.

    Errors:
        OSError, yaml.YAMLError: the contract cannot be loaded.

    Side Effects:
        Network requests; writes the report to stdout.

    Complexity: O(number of checks) requests.
    Thread Safety: not applicable (process-level).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        Requires a running service: ``run(7, "http://digit-7:8080")``.

    See Also: main, checks.
    """
    contract = load_contract()
    plan = checks(digit)
    print(f"# digit contract {contract['info']['version']}: digit-{digit} at {base_url}")
    print(f"1..{len(plan)}")
    failed = 0
    for number, (title, check) in enumerate(plan, start=1):
        try:
            errors = check(base_url, contract)
        except Exception as exc:  # noqa: BLE001 - every failure is reported, not raised
            errors = [f"{type(exc).__name__}: {exc}"]
        print(f"{'not ok' if errors else 'ok'} {number} - {title}")
        for error in errors:
            print(f"#   {error}")
        failed += bool(errors)
    print(f"# {len(plan) - failed} passed, {failed} failed")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    """Parse the command line and run the contract test.

    Summary:
        ``digit_contract.py <digit> <base-url>``.

    Description:
        Validates the digit (0..9) and strips a trailing slash from the URL.

    Business Justification:
        Called by ``tests/contract/digit.sh`` for every digit service.

    Parameters:
        argv (list[str]): arguments without the program name.

    Returns:
        int: 0 all passed, 1 a check failed, 2 usage error.

    Errors:
        As :func:`run`.

    Side Effects:
        As :func:`run`; usage errors go to stderr.

    Complexity: as :func:`run`.
    Thread Safety: not applicable (process entry point).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        >>> import contextlib, io
        >>> with contextlib.redirect_stderr(io.StringIO()):
        ...     main(["12", "http://x"])
        2

    See Also: run.
    """
    if len(argv) != 2 or argv[0] not in [str(d) for d in range(10)]:
        print("usage: digit_contract.py <digit 0-9> <base-url>", file=sys.stderr)
        return 2
    return run(int(argv[0]), argv[1].rstrip("/"))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
