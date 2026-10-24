// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          tests/digit8_tests/transport_test.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Unit tests of the HTTP/1.1 framing on prepared input:
//                  persistent connections, pipelining, split input, bodies,
//                  limits and malformed requests; plus the trace context and
//                  the log lines.
// Related Docs:    services/digit-8/README.md, RFC 9112, ADR-0030

/**
 * Tests of `digit8.http`, `digit8.trace` and `digit8.log`.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8_tests.transport_test;

import digit8.http : maxBody, maxHead;
import digit8.log : Level, Logger;
import digit8.trace : parseTraceparent;
import digit8_tests.support;
import std.algorithm.iteration : map;
import std.algorithm.searching : canFind, count, endsWith;
import std.array : array, replicate;
import std.conv : to;
import std.json : parseJSON;
import std.range : chunks;

// Two requests on one HTTP/1.1 connection are both answered; the
// connection stays open (no Connection: close) until the input ends.
unittest
{
    auto output = serve("GET /value HTTP/1.1\r\nHost: x\r\n\r\n",
            "GET /next HTTP/1.1\r\nHost: x\r\n\r\n");
    assert(statuses(output) == [200, 200]);
    assert(!output.canFind("Connection: close"));
    assert(output.endsWith(`{"digit":8,"next":9,"carry":false}`));
}

// Pipelined requests in one chunk are answered in order.
unittest
{
    auto output = serve(
            "GET /value HTTP/1.1\r\n\r\nGET /nope HTTP/1.1\r\n\r\nGET /next HTTP/1.1\r\n\r\n");
    assert(statuses(output) == [200, 404, 200]);
}

// Input split into single bytes is reassembled.
unittest
{
    auto request = "GET /value?probe=1 HTTP/1.1\r\nHost: x\r\n\r\n";
    auto output = serve(request.chunks(1).map!(c => c.to!string).array);
    assert(statuses(output) == [200]);
    assert(output.endsWith(`{"digit":8,"value":8}`));
}

// Empty lines before the request line are skipped; bare LF line endings
// are accepted.
unittest
{
    assert(statuses(serve("\r\n\nGET /health HTTP/1.1\nHost: x\n\n")) == [200]);
}

// HTTP/1.0 closes after the reply unless it asks for keep-alive.
unittest
{
    auto closed = serve("GET /value HTTP/1.0\r\n\r\nGET /value HTTP/1.0\r\n\r\n");
    assert(statuses(closed) == [200]);
    assert(closed.canFind("Connection: close"));
    auto kept = serve(
            "GET /value HTTP/1.0\r\nConnection: keep-alive\r\n\r\nGET /next HTTP/1.0\r\n\r\n");
    assert(statuses(kept) == [200, 200]);
}

// Connection: close on HTTP/1.1 ends the connection after the reply.
unittest
{
    auto first = "GET /value HTTP/1.1\r\nConnection: Keep-Alive, close\r\n\r\n";
    auto output = serve(first ~ "GET /next HTTP/1.1\r\n\r\n");
    assert(statuses(output) == [200]);
    assert(output.canFind("Connection: close"));
}

// HEAD gets the headers of the 405 without its body.
unittest
{
    auto output = serve("HEAD /value HTTP/1.1\r\n\r\nGET /value HTTP/1.1\r\n\r\n");
    assert(statuses(output) == [405, 200]);
    assert(output.canFind("Allow: GET\r\n\r\nHTTP/1.1 200"));
}

// A Content-Length body is read and skipped, not taken for a request.
unittest
{
    auto output = serve("POST /value HTTP/1.1\r\nContent-Length: 10\r\n\r\n",
            "0123456789", "GET /next HTTP/1.1\r\n\r\n");
    assert(statuses(output) == [405, 200]);
}

// A chunked body with a trailer field is skipped.
unittest
{
    auto output = serve("POST /next HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
            ~ "5;ext=1\r\nhello\r\na\r\n0123456789\r\n0\r\nX-Trailer: 1\r\n\r\n"
            ~ "GET /next HTTP/1.1\r\n\r\n");
    assert(statuses(output) == [405, 200]);
}

// Bodies above the limit answer 413 and close, whichever framing.
unittest
{
    auto byLength = serve("POST /value HTTP/1.1\r\nContent-Length: " ~ (maxBody + 1)
            .to!string ~ "\r\n\r\n");
    assert(statuses(byLength) == [413] && byLength.canFind("Connection: close"));
    auto exact = serve("POST /value HTTP/1.1\r\nContent-Length: " ~ maxBody.to!string ~ "\r\n\r\n",
            "x".replicate(maxBody), "GET /value HTTP/1.1\r\n\r\n");
    assert(statuses(exact) == [405, 200]);
    auto chunked = serve("POST /value HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n10001\r\n");
    assert(statuses(chunked) == [413]);
}

// Ambiguous or invalid framing answers 400 and closes.
unittest
{
    foreach (request; [
        "POST /value HTTP/1.1\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n",
        "POST /value HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n",
        "POST /value HTTP/1.1\r\nContent-Length: -1\r\n\r\n",
        "POST /value HTTP/1.1\r\nContent-Length: 1, 1\r\n\r\n",
        "POST /value HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\n",
        "POST /value HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n",
        "POST /value HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabcX\r\n",
    ])
    {
        auto output = serve(request);
        assert(statuses(output) == [400], request);
        assert(output.canFind("Connection: close"));
    }
}

// A truncated body answers 400.
unittest
{
    assert(statuses(serve("POST /value HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc")) == [
        400
    ]);
}

// Malformed heads answer 400 problem details.
unittest
{
    foreach (request; [
        "garbage\r\n\r\n", "GET /value HTTP/2.0\r\n\r\n",
        "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n", "GET  /value HTTP/1.1\r\n\r\n",
        "G(T /value HTTP/1.1\r\n\r\n", "GET /value HTTP/1.1\r\nno colon\r\n\r\n",
        "GET /value HTTP/1.1\r\n folded: x\r\n\r\n",
        "GET /value HTTP/1.1\r\nHost: x\r\n",
    ])
    {
        auto output = serve(request);
        assert(statuses(output) == [400], request);
        assert(output.canFind("application/problem+json"));
    }
}

// Heads above 8 KiB answer 431, whether one line or many is too long.
unittest
{
    auto longLine = serve("GET /" ~ "a".replicate(maxHead) ~ " HTTP/1.1\r\n\r\n");
    assert(statuses(longLine) == [431]);
    string many = "GET /value HTTP/1.1\r\n";
    foreach (i; 0 .. 200)
    {
        many ~= "X-Header-" ~ i.to!string ~ ": " ~ "v".replicate(40) ~ "\r\n";
    }
    assert(statuses(serve(many ~ "\r\n")) == [431]);
    auto unterminated = serve("GET /value HTTP/1.1\r\nX: " ~ "v".replicate(maxHead));
    assert(statuses(unterminated) == [431]);
}

// A head just under the limit is answered.
unittest
{
    auto head = "GET /value HTTP/1.1\r\nX: ";
    auto filler = "v".replicate(maxHead - head.length - 4);
    assert(statuses(serve(head ~ filler ~ "\r\n\r\n")) == [200]);
    assert(statuses(serve(head ~ filler ~ "v\r\n\r\n")) == [431]);
}

// An input that ends before a request line is a clean end: no reply.
unittest
{
    assert(serve() == "");
    assert(serve("GET /val") == "");
    assert(serve("\r\n") == "");
}

// The reply has the headers of the contract and a JSON body.
unittest
{
    auto output = serve("GET /value HTTP/1.1\r\n\r\n");
    assert(output.canFind("\r\nDate: ") && output.canFind(" GMT\r\n"));
    assert(output.canFind("\r\nContent-Type: application/json\r\nContent-Length: 21\r\n\r\n"));
}

// A valid traceparent reaches the debug line of the request; an invalid
// one is ignored.
unittest
{
    auto capture = new Capture();
    auto fixture = contract();
    auto traced = "GET /next HTTP/1.1\r\n"
        ~ "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01\r\n\r\n";
    auto invalid = "GET /value HTTP/1.1\r\ntraceparent: 00-0000-00f067aa0ba902b7-01\r\n\r\n";
    serveOn(new FakeConnection([traced ~ invalid]), fixture.api, capture.logger());
    auto lines = capture.lines();
    assert(lines.length == 2);
    auto first = parseJSON(lines[0]);
    assert(first["msg"].str == "request answered" && first["detail"].str == "GET /next -> 200");
    assert(first["traceId"].str == "4bf92f3577b34da6a3ce929d0e0e4736");
    assert(first["spanId"].str == "00f067aa0ba902b7");
    assert(parseJSON(lines[1])["traceId"].isNull);
}

// Invalid traceparent values are rejected.
unittest
{
    foreach (header; [
        "", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7",
        "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
        "00-00000000000000000000000000000000-00f067aa0ba902b7-01",
        "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",
        "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01",
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-1",
    ])
    {
        assert(parseTraceparent(header).isNull, header);
    }
}

// Log lines are valid JSON with every field of CLAUDE.md 6.1, whatever
// the detail holds; lines below the threshold are dropped.
unittest
{
    auto capture = new Capture();
    auto log = capture.logger(Level.info);
    log.write(Level.debug_, "dropped");
    log.write(Level.warn, "quoted \"msg\"", "line\nbreak\x01 and ł");
    log.write(Level.error, "traced", null, "4bf92f3577b34da6a3ce929d0e0e4736", "00f067aa0ba902b7");
    auto lines = capture.lines();
    assert(lines.length == 2);
    auto first = parseJSON(lines[0]);
    assert(first["level"].str == "warn" && first["service"].str == "digit-8");
    assert(first["msg"].str == "quoted \"msg\"");
    assert(first["detail"].str == "line\nbreak\x01 and ł");
    assert(first["taskId"].isNull && first["traceId"].isNull && first["spanId"].isNull);
    assert(first["ts"].str.length == 24 && first["ts"].str.endsWith("Z"));
    auto second = parseJSON(lines[1]);
    assert(second["traceId"].str == "4bf92f3577b34da6a3ce929d0e0e4736");
    assert("detail" !in second.object);
}
