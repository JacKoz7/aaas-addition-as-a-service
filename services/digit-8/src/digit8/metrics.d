// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          src/digit8/metrics.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Prometheus metrics of the digit service: the request
//                  counter shared by all ten digit services and the build
//                  information.
// Related Docs:    contracts/http/digit.yaml (GET /metrics), ADR-0021

/**
 * Prometheus metrics of the digit-8 service.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8.metrics;

import std.array : appender;
import std.format : formattedWrite;

/**
 * Arithmetic endpoint, label `endpoint` of the counter.
 *
 * Thread_Safety: a value type. Owner: AEC. Since: digit-8 0.1.0.
 */
enum Endpoint
{
    /// GET /value.
    value,
    /// GET /next.
    next,
}

/**
 * Outcome of a request, label `outcome` of the counter.
 *
 * Thread_Safety: a value type. Owner: AEC. Since: digit-8 0.1.0.
 */
enum Outcome
{
    /// Answered 200.
    ok,
    /// Answered 503 (database unavailable).
    error,
}

/**
 * Counters of one service process; every sample exists from the start
 * (value 0).
 *
 * Business_Justification: one dashboard shows the traffic of all ten digit
 * services (P7.3).
 *
 * Thread_Safety: not synchronised; used only through `digit8.api.Api`,
 * which the server calls under one mutex (ADR-0030).
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
final class Metrics
{
    /// Value of the `digit` label, 0..9.
    immutable int digit;
    /// Service version for `digit_build_info`.
    immutable string version_;
    /// `digit_requests_total` samples, indexed by endpoint and outcome.
    private ulong[2][2] requests;

    /**
     * Create zeroed counters.
     *
     * Params:
     *   digit = the service's digit, 0..9.
     *   version_ = the service version.
     *
     * Errors: none. Side Effects: none. Complexity: O(1).
     * Thread Safety: not applicable. Owner: AEC. Since: digit-8 0.1.0.
     */
    this(int digit, string version_) pure nothrow @safe
    {
        this.digit = digit;
        this.version_ = version_;
    }

    /**
     * Count one answered request.
     *
     * Business_Justification: traffic and errors per digit.
     *
     * Params:
     *   endpoint = the endpoint answered.
     *   outcome = the outcome of the request.
     *
     * Errors: none. Side Effects: increments one counter. Complexity: O(1).
     * Thread Safety: under the server's mutex. Owner: AEC.
     * Since: digit-8 0.1.0.
     */
    void count(Endpoint endpoint, Outcome outcome) pure nothrow @safe @nogc
    {
        requests[endpoint][outcome]++;
    }

    /**
     * Current value of one sample (used by the unit tests).
     *
     * Params:
     *   endpoint = the endpoint.
     *   outcome = the outcome.
     * Returns: the number of counted requests.
     *
     * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
     * under the server's mutex. Owner: AEC. Since: digit-8 0.1.0.
     */
    ulong get(Endpoint endpoint, Outcome outcome) const pure nothrow @safe @nogc
    {
        return requests[endpoint][outcome];
    }

    /**
     * Render the Prometheus text exposition (format 0.0.4).
     *
     * Description: `digit_requests_total` with the labels digit, endpoint
     * and outcome (all four samples) and `digit_build_info` with the labels
     * digit and version, value 1.
     *
     * Business_Justification: GET /metrics of the contract.
     *
     * Returns: the exposition text.
     *
     * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
     * under the server's mutex. Owner: AEC. Since: digit-8 0.1.0.
     */
    string render() const @safe
    {
        enum sample = "digit_requests_total{digit=\"%d\",endpoint=\"%s\"," ~ "outcome=\"%s\"} %d\n";
        auto text = appender!string();
        text ~= "# HELP digit_requests_total Requests answered by the digit service.\n";
        text ~= "# TYPE digit_requests_total counter\n";
        foreach (endpoint; [Endpoint.value, Endpoint.next])
        {
            foreach (outcome; [Outcome.ok, Outcome.error])
            {
                text.formattedWrite!(sample)(digit, endpoint, outcome, get(endpoint, outcome));
            }
        }
        text ~= "# HELP digit_build_info Build information of the digit service.\n";
        text ~= "# TYPE digit_build_info gauge\n";
        text.formattedWrite!"digit_build_info{digit=\"%d\",version=\"%s\"} 1\n"(digit, version_);
        return text[];
    }
}

///
unittest
{
    import std.algorithm.searching : canFind;

    auto metrics = new Metrics(8, "0.1.0");
    metrics.count(Endpoint.next, Outcome.ok);
    assert(metrics.get(Endpoint.next, Outcome.ok) == 1);
    auto text = metrics.render();
    assert(text.canFind(`digit_requests_total{digit="8",endpoint="next",outcome="ok"} 1`));
    assert(text.canFind(`digit_requests_total{digit="8",endpoint="value",outcome="error"} 0`));
    assert(text.canFind(`digit_build_info{digit="8",version="0.1.0"} 1`));
}
