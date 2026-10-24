// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          src/digit8/api.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         The HTTP contract of the digit service as a function
//                  from (method, path) to a reply: routing, JSON bodies,
//                  problem details, health and metrics.
// Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022

/**
 * The digit contract (`contracts/http/digit.yaml`) of the digit-8 service.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8.api;

import digit8.log : jsonEscape, Level, Logger;
import digit8.metrics : Endpoint, Metrics, Outcome;
import digit8.store : DigitRow, Store, StoreException;
import std.format : format;
import std.typecons : Nullable, nullable;

/// Media type of JSON bodies.
enum string jsonType = "application/json";

/// Media type of problem details (RFC 9457).
enum string problemType = "application/problem+json";

/// Media type of the Prometheus text exposition.
enum string prometheusType = "text/plain; version=0.0.4";

/// Paths of the contract.
private immutable string[] paths = ["/value", "/next", "/health", "/metrics"];

/**
 * An HTTP reply to send.
 *
 * Thread_Safety: a value type. Owner: Arithmetic Excellence Center (AEC).
 * Since: digit-8 0.1.0.
 */
struct Reply
{
    /// HTTP status code.
    int status;
    /// Value of Content-Type.
    string contentType;
    /// Response body.
    string body;
    /// Value of Allow; `null` when not sent (405 only).
    string allow;
}

/**
 * Build a problem details reply (RFC 9457).
 *
 * Description: `type` is `about:blank`; the title and the detail are
 * JSON-escaped.
 *
 * Business_Justification: every AaaS error is problem details
 * (CLAUDE.md 4.1).
 *
 * Params:
 *   status = the HTTP status.
 *   title = a short summary of the problem type.
 *   detail = an explanation of this occurrence.
 *   allow = the value of Allow, for 405; `null` otherwise.
 * Returns: the reply with Content-Type `application/problem+json`.
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 *
 * See_Also: `Api.handle`.
 */
Reply problem(int status, string title, string detail, string allow = null) pure @safe
{
    return Reply(status, problemType,
            format!`{"type":"about:blank","title":"%s","status":%d,"detail":"%s"}`(
                jsonEscape(title), status, jsonEscape(detail)), allow);
}

///
unittest
{
    auto reply = problem(404, "Not Found", "no \"such\" path");
    assert(reply.status == 404 && reply.contentType == problemType && reply.allow is null);
    assert(reply.body == `{"type":"about:blank","title":"Not Found","status":404,`
            ~ `"detail":"no \"such\" path"}`);
}

/**
 * The digit contract over one database.
 *
 * Description: holds references to the store and the metrics, which must
 * outlive it.
 *
 * Business_Justification: the single implementation of the contract that
 * every digit request goes through; the value is read on every request,
 * never cached or hard-coded (CLAUDE.md 4.4).
 *
 * Thread_Safety: not synchronised; the server calls it under one mutex,
 * which also covers the store and the metrics it holds (ADR-0030).
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
final class Api
{
    /// Database of the service.
    private Store store;
    /// The configured digit (`AAAS_DIGIT`).
    private immutable int digit;
    /// Request counters.
    private Metrics metrics;
    /// Logger for database failures.
    private Logger log;

    /**
     * Bind the contract to a database and counters; nothing is read until
     * the first request.
     *
     * Params:
     *   store = the open, migrated database of the service.
     *   digit = the digit the service represents, 0..9.
     *   metrics = the counters updated by /value and /next.
     *   log = the logger for database failures.
     *
     * Errors: none. Side Effects: none. Complexity: O(1).
     * Thread Safety: not applicable. Owner: AEC. Since: digit-8 0.1.0.
     *
     * Examples: `auto api = new Api(store, 8, metrics, log);`
     *
     * See_Also: `handle`.
     */
    this(Store store, int digit, Metrics metrics, Logger log) pure nothrow @safe
    {
        this.store = store;
        this.digit = digit;
        this.metrics = metrics;
        this.log = log;
    }

    /**
     * Read the digit row and check that it names the configured digit.
     *
     * Description: a failure is logged at error level.
     *
     * Business_Justification: a service must never answer for another
     * digit, for example after its volume was mixed up with another one.
     *
     * Returns: the row, or an empty `Nullable` on failure.
     *
     * Errors: none (empty result). Side Effects: one SELECT; logs failures.
     * Complexity: O(1). Thread Safety: under the server's mutex.
     * Owner: AEC. Since: digit-8 0.1.0.
     *
     * See_Also: `Store.read`.
     */
    private Nullable!DigitRow readRow() @safe
    {
        DigitRow row;
        try
        {
            row = store.read();
        }
        catch (StoreException error)
        {
            log.write(Level.error, "cannot read the digit from the database", error.msg);
            return Nullable!DigitRow.init;
        }
        if (row.digit != digit)
        {
            log.write(Level.error, "the database holds another digit");
            return Nullable!DigitRow.init;
        }
        return nullable(row);
    }

    /**
     * Answer GET /value or GET /next.
     *
     * Description: reads the row on every call; 503 problem details when
     * it cannot be read. Counts the request in the metrics.
     *
     * Business_Justification: the arithmetic of the digit (CLAUDE.md 4.4).
     *
     * Params:
     *   endpoint = which of the two operations.
     * Returns: the reply.
     *
     * Errors: none (503 reply). Side Effects: one SELECT; one counter
     * increment. Complexity: O(1). Thread Safety: under the server's mutex.
     * Owner: AEC. Since: digit-8 0.1.0.
     */
    private Reply answerDigit(Endpoint endpoint) @safe
    {
        auto row = readRow();
        if (row.isNull)
        {
            metrics.count(endpoint, Outcome.error);
            return problem(503, "Service Unavailable",
                    "the digit cannot be read from the database; retry the call");
        }
        metrics.count(endpoint, Outcome.ok);
        final switch (endpoint)
        {
        case Endpoint.value:
            return Reply(200, jsonType,
                    format!`{"digit":%d,"value":%d}`(row.get.digit, row.get.value));
        case Endpoint.next:
            return Reply(200, jsonType,
                    format!`{"digit":%d,"next":%d,"carry":%s}`(row.get.digit,
                        row.get.next, row.get.carry));
        }
    }

    /**
     * Answer one request according to contracts/http/digit.yaml.
     *
     * Description: GET /value answers 200 with digit and value; GET /next
     * 200 with digit, next and carry, both from the database; GET /health
     * 200 with status ok and checks.database ok when the row can be read
     * and names the configured digit, otherwise 503 with error; GET
     * /metrics 200 Prometheus text; another method on one of these paths
     * 405 problem details with Allow: GET; any other path 404 problem
     * details. When the row cannot be read or names another digit, /value
     * and /next answer 503 problem details and count an error.
     *
     * Business_Justification: the arithmetic of the digit (CLAUDE.md 4.4).
     *
     * Params:
     *   method = the HTTP method, as received.
     *   path = the request path without the query string.
     * Returns: the reply.
     *
     * Errors: none (404, 405 or 503 replies). Side Effects: reads the
     * database; updates the metrics; logs database failures.
     * Complexity: O(1). Thread Safety: under the server's mutex.
     * Owner: AEC. Since: digit-8 0.1.0.
     *
     * Examples: `auto reply = api.handle("GET", "/next");`
     *
     * See_Also: `problem`.
     */
    Reply handle(string method, string path) @safe
    {
        import std.algorithm.searching : canFind;

        if (!paths.canFind(path))
        {
            return problem(404, "Not Found", "the digit service has no such path");
        }
        if (method != "GET")
        {
            return problem(405, "Method Not Allowed", "only GET is allowed on this path", "GET");
        }
        switch (path)
        {
        case "/value":
            return answerDigit(Endpoint.value);
        case "/next":
            return answerDigit(Endpoint.next);
        case "/health":
            return readRow().isNull ? Reply(503, jsonType,
                    `{"status":"error","checks":{"database":"error"}}`) : Reply(200,
                    jsonType, `{"status":"ok","checks":{"database":"ok"}}`);
        default:
            return Reply(200, prometheusType, metrics.render());
        }
    }
}
