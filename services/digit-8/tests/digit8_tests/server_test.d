// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          tests/digit8_tests/server_test.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Unit tests of the server over TCP on the loopback
//                  interface (keep-alive, connection limit, graceful stop,
//                  port in use) and of the configuration and start-up
//                  checks of digit8.service.
// Related Docs:    services/digit-8/README.md, CLAUDE.md 6.1, ADR-0030

/**
 * Tests of `digit8.server` and `digit8.service`.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8_tests.server_test;

import core.thread : Thread;
import core.time : MonoTime, msecs, seconds;
import digit8.server : DigitServer, maxConnections, ServerException;
import digit8.service : loadConfig, run;
import digit8_tests.support;
import std.algorithm.searching : canFind, endsWith;
import std.exception : assertThrown;
import std.process : environment;
import std.socket : InternetAddress, Socket, SocketOption, SocketOptionLevel, TcpSocket;

/**
 * Connect to the server on the loopback interface.
 *
 * Params:
 *   server = the running server.
 * Returns: the connected socket, with a 2 s receive timeout.
 *
 * Errors: a `SocketException` fails the test. Side Effects: opens a
 * connection. Complexity: O(1). Thread Safety: one test. Owner: AEC.
 * Since: digit-8 0.1.0.
 */
Socket connectTo(DigitServer server) @trusted
{
    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", server.port));
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 2.seconds);
    return socket;
}

/**
 * Read from a socket until the text received ends with `suffix`, the
 * connection ends or the receive timeout passes.
 *
 * Params:
 *   socket = the socket.
 *   suffix = the expected end of the input.
 * Returns: everything received.
 *
 * Errors: none. Side Effects: reads the socket. Complexity: O(n).
 * Thread Safety: one test. Owner: AEC. Since: digit-8 0.1.0.
 */
string readUntil(Socket socket, string suffix) @trusted
{
    string received;
    ubyte[4096] buffer;
    while (!received.endsWith(suffix))
    {
        auto count = socket.receive(buffer[]);
        if (count <= 0)
        {
            break;
        }
        received ~= cast(string) buffer[0 .. count].idup;
    }
    return received;
}

/**
 * Read from a socket until the peer closes it or the timeout passes.
 *
 * Params:
 *   socket = the socket.
 * Returns: everything received.
 *
 * Errors: none. Side Effects: reads the socket. Complexity: O(n).
 * Thread Safety: one test. Owner: AEC. Since: digit-8 0.1.0.
 */
string readAll(Socket socket) @trusted
{
    return readUntil(socket, "\0never\0");
}

/**
 * A server for digit 8 on a free loopback port.
 *
 * Params:
 *   capture = receives the log lines.
 * Returns: the running server.
 *
 * Errors: a `ServerException` fails the test. Side Effects: opens a
 * socket and starts threads. Complexity: O(1). Thread Safety: one test.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
DigitServer startServer(Capture capture) @safe
{
    auto fixture = contract();
    return new DigitServer(0, fixture.api, capture.logger());
}

// Requests over TCP on one keep-alive connection, then a graceful stop
// that closes the idle connection at once.
unittest
{
    auto capture = new Capture();
    auto server = startServer(capture);
    auto client = connectTo(server);
    client.send("GET /value HTTP/1.1\r\nHost: x\r\n\r\n");
    assert(readUntil(client, `{"digit":8,"value":8}`).canFind("HTTP/1.1 200 OK"));
    client.send("GET /next HTTP/1.1\r\nHost: x\r\n\r\n");
    assert(readUntil(client, "}").endsWith(`{"digit":8,"next":9,"carry":false}`));
    auto started = MonoTime.currTime;
    server.stop();
    assert(MonoTime.currTime - started < 1.seconds);
    assert(readAll(client) == "");
    client.close();
}

// A request running during the stop is answered with Connection: close.
unittest
{
    auto capture = new Capture();
    auto server = startServer(capture);
    auto client = connectTo(server);
    client.send("GET /value HTTP/1.1\r\nContent-Length: 5\r\n\r\nab");
    Thread.sleep(100.msecs);
    auto stopper = new Thread(() => server.stop());
    stopper.start();
    Thread.sleep(100.msecs);
    client.send("cde");
    auto reply = readAll(client);
    stopper.join();
    assert(reply.canFind("HTTP/1.1 200 OK") && reply.canFind("Connection: close"));
    client.close();
}

// Above the connection limit, new connections are closed at once and a
// warning is logged; the admitted ones are served.
unittest
{
    auto capture = new Capture();
    auto server = startServer(capture);
    Socket[] clients;
    foreach (i; 0 .. maxConnections)
    {
        clients ~= connectTo(server);
    }
    auto extra = connectTo(server);
    assert(readAll(extra) == "");
    clients[$ - 1].send("GET /health HTTP/1.1\r\n\r\n");
    assert(readUntil(clients[$ - 1], "}").canFind("HTTP/1.1 200 OK"));
    assert(capture.lines().canFind!(line => line.canFind("connection limit reached")));
    foreach (client; clients)
    {
        client.close();
    }
    extra.close();
    server.stop();
}

/**
 * The number of memory mappings of this process.
 *
 * Returns: the line count of `/proc/self/maps` (Linux).
 *
 * Errors: a `FileException` fails the test. Side Effects: reads procfs.
 * Complexity: O(m). Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
 */
size_t mappings() @safe
{
    import std.algorithm.searching : count;
    import std.file : readText;

    return readText("/proc/self/maps").count('\n');
}

/**
 * Open a connection, send one closing request and read the reply.
 *
 * Params:
 *   server = the running server.
 *
 * Errors: a `SocketException` fails the test. Side Effects: one
 * connection. Complexity: O(1). Thread Safety: one test. Owner: AEC.
 * Since: digit-8 0.1.0.
 */
void callOnce(DigitServer server) @trusted
{
    auto client = connectTo(server);
    client.send("GET /value HTTP/1.1\r\nConnection: close\r\n\r\n");
    readAll(client);
    client.close();
}

// Ended connection threads are joined: 100 connections do not leave 100
// thread stacks (two mappings each) behind.
unittest
{
    auto server = startServer(new Capture());
    foreach (i; 0 .. 10)
    {
        callOnce(server);
    }
    Thread.sleep(300.msecs);
    auto before = mappings();
    foreach (i; 0 .. 100)
    {
        callOnce(server);
    }
    Thread.sleep(300.msecs);
    assert(mappings() < before + 20);
    server.stop();
}

// A port in use fails the start with the system message.
unittest
{
    auto capture = new Capture();
    auto first = startServer(capture);
    auto fixture = contract();
    assertThrown!ServerException(new DigitServer(first.port, fixture.api, capture.logger()));
    first.stop();
}

// The configuration accepts the defaults and refuses invalid values; run
// stops with status 1 before serving when a check fails.
unittest
{
    scope (exit)
    {
        foreach (name; [
            "AAAS_BOOTSTRAP", "AAAS_DIGIT", "AAAS_HTTP_PORT", "AAAS_DB_PATH",
            "AAAS_MIGRATIONS_DIR", "AAAS_LOG_LEVEL"
        ])
        {
            environment.remove(name);
        }
    }
    auto capture = new Capture();
    auto config = loadConfig(capture.logger());
    assert(!config.isNull);
    assert(config.get.digit == 8 && config.get.port == 8080);
    assert(config.get.dbPath == "/data/digit-8.db");
    assert(config.get.migrationsDir == "/app/migrations");

    foreach (setting; [
            ["AAAS_BOOTSTRAP", "platform"], ["AAAS_DIGIT", "x"],
            ["AAAS_DIGIT", "10"], ["AAAS_HTTP_PORT", "0"],
            ["AAAS_HTTP_PORT", "65536"],
        ])
    {
        environment[setting[0]] = setting[1];
        assert(loadConfig(capture.logger()).isNull, setting[0] ~ "=" ~ setting[1]);
        environment.remove(setting[0]);
    }

    environment["AAAS_LOG_LEVEL"] = "error";
    environment["AAAS_DB_PATH"] = ":memory:";
    environment["AAAS_MIGRATIONS_DIR"] = "/nonexistent/migrations";
    assert(run() == 1);
    environment["AAAS_MIGRATIONS_DIR"] = migrationsDir;
    environment["AAAS_DIGIT"] = "5";
    assert(run() == 1);
}
