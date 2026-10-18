# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          tests/contract/stub/digit_stub.py
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Test double of a digit service, used only by
#                  tests/contract/selftest.sh to prove that the contract
#                  test accepts a conforming service and rejects a faulty
#                  one. Not a digit service: it is never deployed.
# Related Docs:    tests/contract/README.md, contracts/http/digit.yaml, ADR-0021
"""Digit service test double.

Summary:
    Minimal HTTP server that speaks ``contracts/http/digit.yaml``.

Description:
    ``DIGIT`` (0..9) selects the digit; ``FAULT`` injects one defect so that
    the self-test can show the contract test failing:

    - ``none`` (default): conforming behaviour;
    - ``wrong-next``: ``/next`` answers ``digit + 2``;
    - ``plain-errors``: errors are ``text/plain`` instead of problem+json.

    Listens on port 8080 like every AaaS service. Real digit services read
    their digit from SQLite (``CLAUDE.md`` 4.4); the double does not need
    to, because the contract test cannot observe it.

Business Justification:
    A test that has never been seen failing proves nothing; the self-test
    exercises both outcomes before any real digit service exists.

Owner: Arithmetic Excellence Center (AEC)
Since: contract-tests 0.1.0
See Also: tests/contract/digit_contract.py, tests/contract/selftest.sh.
"""

from __future__ import annotations

import json
import os
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

#: Digit served by this process.
DIGIT = int(os.environ.get("DIGIT", "0"))

#: Injected defect (see the module documentation).
FAULT = os.environ.get("FAULT", "none")

#: Requests answered, keyed by (endpoint, outcome), for /metrics.
COUNTS: Counter[tuple[str, str]] = Counter()


def answer(path: str) -> dict[str, object] | None:
    """Compute the JSON answer of a GET path.

    Summary:
        Body of ``/value``, ``/next`` or ``/health``; None for other paths.

    Description:
        ``/next`` follows base 10 (``carry`` only for 9) unless the fault
        ``wrong-next`` is active.

    Business Justification:
        The arithmetic the contract test checks.

    Parameters:
        path (str): request path.

    Returns:
        dict[str, object] | None: the body, or None when the path is unknown.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(1).
    Thread Safety: safe (reads module constants).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        >>> answer("/next") == {"digit": DIGIT, "next": (DIGIT + 1) % 10, "carry": DIGIT == 9}
        True
        >>> answer("/nope") is None
        True

    See Also: Handler.do_GET.
    """
    step = 2 if FAULT == "wrong-next" else 1
    return {
        "/value": {"digit": DIGIT, "value": DIGIT},
        "/next": {"digit": DIGIT, "next": (DIGIT + step) % 10, "carry": DIGIT + step > 9},
        "/health": {"status": "ok", "checks": {"database": "ok"}},
    }.get(path)


def metrics() -> str:
    """Render the Prometheus exposition of the request counter.

    Summary:
        ``digit_requests_total`` with the labels of the contract.

    Description:
        One sample per (endpoint, outcome) seen so far.

    Business Justification:
        The contract test checks the counter.

    Parameters:
        None.

    Returns:
        str: text exposition format.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(k) in the number of samples.
    Thread Safety: reads a Counter that handler threads update; good enough
        for a test double.
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        >>> metrics().splitlines()[1]
        '# TYPE digit_requests_total counter'

    See Also: Handler.do_GET.
    """
    lines = [
        "# HELP digit_requests_total Requests answered by the digit service.",
        "# TYPE digit_requests_total counter",
    ]
    for (endpoint, outcome), value in sorted(COUNTS.items()):
        lines.append(f'digit_requests_total{{digit="{DIGIT}",endpoint="{endpoint}",outcome="{outcome}"}} {value}')
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    """HTTP handler of the test double.

    Summary:
        Serves GET on the contract's paths; everything else is an error.

    Description:
        Unknown paths answer 404, other methods on known paths 405 with
        ``Allow: GET``, both as problem details unless the fault
        ``plain-errors`` is active.

    Business Justification:
        See the module documentation.

    Parameters:
        Not applicable (instantiated by the server per request).

    Returns:
        Not applicable (class).

    Errors:
        None.

    Side Effects:
        Writes HTTP responses.

    Complexity: O(1) per request.
    Thread Safety: one instance per request.
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        Run ``python3 digit_stub.py`` and ``curl localhost:8080/next``.

    See Also: main.
    """

    #: Paths of the contract.
    PATHS = ("/value", "/next", "/health", "/metrics")

    def send(self, status: int, media_type: str, body: str, headers: dict[str, str] | None = None) -> None:
        """Write one complete response.

        Summary:
            Status line, headers and body.

        Description:
            Sets ``Content-Type`` and ``Content-Length``.

        Business Justification:
            Shared by every answer of the handler.

        Parameters:
            status (int): HTTP status.
            media_type (str): value of ``Content-Type``.
            body (str): response body.
            headers (dict[str, str] | None): extra headers.

        Returns:
            None.

        Errors:
            OSError: the client went away.

        Side Effects:
            Writes to the socket.

        Complexity: O(n) in the body length.
        Thread Safety: one handler per request.
        Owner: Arithmetic Excellence Center (AEC)
        Since: contract-tests 0.1.0

        Example:
            ``self.send(200, "application/json", "{}")``.

        See Also: Handler.problem.
        """
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", media_type)
        self.send_header("Content-Length", str(len(data)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(data)

    def problem(self, status: int, title: str, headers: dict[str, str] | None = None) -> None:
        """Answer an error as problem details (RFC 9457).

        Summary:
            ``application/problem+json`` with type, title and status.

        Description:
            With the fault ``plain-errors``, answers ``text/plain`` instead.

        Business Justification:
            The contract's error format.

        Parameters:
            status (int): HTTP status.
            title (str): problem title.
            headers (dict[str, str] | None): extra headers.

        Returns:
            None.

        Errors:
            OSError: the client went away.

        Side Effects:
            Writes to the socket.

        Complexity: O(1).
        Thread Safety: one handler per request.
        Owner: Arithmetic Excellence Center (AEC)
        Since: contract-tests 0.1.0

        Example:
            ``self.problem(404, "Not Found")``.

        See Also: Handler.send.
        """
        if FAULT == "plain-errors":
            self.send(status, "text/plain", title, headers)
            return
        body = json.dumps({"type": "about:blank", "title": title, "status": status})
        self.send(status, "application/problem+json", body, headers)

    def do_GET(self) -> None:  # noqa: N802 - name fixed by BaseHTTPRequestHandler
        """Serve a GET request.

        Summary:
            JSON operations, metrics, or 404.

        Description:
            Counts ``/value`` and ``/next`` in :data:`COUNTS`.

        Business Justification:
            See the module documentation.

        Parameters:
            None.

        Returns:
            None.

        Errors:
            OSError: the client went away.

        Side Effects:
            Writes to the socket; updates the counter.

        Complexity: O(1).
        Thread Safety: one handler per request.
        Owner: Arithmetic Excellence Center (AEC)
        Since: contract-tests 0.1.0

        Example:
            ``curl localhost:8080/value``.

        See Also: answer, metrics.
        """
        if self.path == "/metrics":
            self.send(200, "text/plain; version=0.0.4", metrics())
            return
        body = answer(self.path)
        if body is None:
            self.problem(404, "Not Found")
            return
        if self.path in ("/value", "/next"):
            COUNTS[(self.path[1:], "ok")] += 1
        self.send(200, "application/json", json.dumps(body))

    def do_POST(self) -> None:  # noqa: N802 - name fixed by BaseHTTPRequestHandler
        """Reject a POST request.

        Summary:
            405 with ``Allow: GET`` on known paths, 404 elsewhere.

        Description:
            The contract has only GET operations.

        Business Justification:
            See the module documentation.

        Parameters:
            None.

        Returns:
            None.

        Errors:
            OSError: the client went away.

        Side Effects:
            Writes to the socket.

        Complexity: O(1).
        Thread Safety: one handler per request.
        Owner: Arithmetic Excellence Center (AEC)
        Since: contract-tests 0.1.0

        Example:
            ``curl -X POST localhost:8080/value``.

        See Also: Handler.problem.
        """
        if self.path in self.PATHS:
            self.problem(405, "Method Not Allowed", {"Allow": "GET"})
        else:
            self.problem(404, "Not Found")


def main() -> None:
    """Serve on port 8080 until terminated.

    Summary:
        Entry point of the test double.

    Description:
        Threading server bound to all interfaces of the container.

    Business Justification:
        See the module documentation.

    Parameters:
        None.

    Returns:
        None (runs until killed).

    Errors:
        OSError: the port is taken.

    Side Effects:
        Opens a listening socket.

    Complexity: not applicable.
    Thread Safety: not applicable (process entry point).
    Owner: Arithmetic Excellence Center (AEC)
    Since: contract-tests 0.1.0

    Example:
        ``DIGIT=7 python3 digit_stub.py``.

    See Also: Handler.
    """
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()  # noqa: S104 - container-internal


if __name__ == "__main__":
    main()
