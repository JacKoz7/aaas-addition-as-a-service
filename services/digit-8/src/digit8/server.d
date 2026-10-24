// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          src/digit8/server.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Minimal HTTP/1.1 server on TCP sockets: one thread per
//                  connection, persistent connections, a connection cap,
//                  a lingering close and a graceful stop.
// Related Docs:    services/digit-8/README.md, contracts/http/digit.yaml,
//                  ADR-0030

/**
 * The HTTP server of the digit-8 service.
 *
 * An accept thread starts one druntime thread per connection; the
 * contract is called under one mutex, so the store and the metrics are
 * never used concurrently. The framing is in `digit8.http`.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8.server;

import core.stdc.errno : EINTR, errno;
import core.sync.mutex : Mutex;
import core.sys.posix.sys.socket : MSG_NOSIGNAL, posixSend = send, recv,
    SHUT_RD, SHUT_RDWR, shutdown;
import core.thread : Thread;
import core.time : msecs, seconds;
import digit8.api : Api, Reply;
import digit8.http : Connection, serveConnection;
import digit8.log : Level, Logger;
import std.conv : to;
import std.socket : InternetAddress, Socket, socket_t, SocketAcceptException,
    SocketException, SocketOption, SocketOptionLevel, SocketShutdown, TcpSocket;

/// Most connections served at once; further ones are closed on accept.
enum size_t maxConnections = 256;

/// Seconds a connection may stay silent, between requests or within one,
/// before it is closed.
enum int idleTimeoutSeconds = 10;

/// Seconds the server waits for running requests after a stop.
private enum int drainTimeoutSeconds = 5;

/// Milliseconds unread input is still read and discarded after the last
/// reply, before the socket is closed.
private enum int lingerMilliseconds = 200;

/// Most bytes discarded after the last reply; a client still sending more
/// is cut off.
private enum size_t lingerBytes = 16_384;

/// Stack size of a connection thread, in bytes: the handler is shallow, so
/// 256 threads stay within a few MiB of resident memory.
private enum size_t threadStackSize = 256 * 1024;

/**
 * A failure to start the server.
 *
 * Thread_Safety: immutable after construction.
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
final class ServerException : Exception
{
    /**
     * Create the exception.
     *
     * Params:
     *   message = the system error message.
     *   file = source file of the throw (filled in by the compiler).
     *   line = source line of the throw (filled in by the compiler).
     *
     * Errors: none. Side Effects: none. Complexity: O(1).
     * Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow @safe
    {
        super(message, file, line);
    }
}

/**
 * A TCP connection of the server.
 *
 * Description: reads and writes go to the descriptor directly, so an
 * interrupted call (`EINTR`, for example while the garbage collector
 * suspends the threads) is retried instead of ending the connection.
 *
 * Thread_Safety: used by its connection thread; the server may only shut
 * its descriptor down from another thread.
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
final class SocketConnection : Connection
{
    /// The accepted socket.
    private Socket socket;

    /**
     * Wrap an accepted socket and set its options.
     *
     * Description: TCP_NODELAY and a receive timeout of
     * `idleTimeoutSeconds`.
     *
     * Params:
     *   socket = the accepted socket.
     *
     * Errors: none (options are best effort). Side Effects: sets socket
     * options. Complexity: O(1). Thread Safety: one thread. Owner: AEC.
     * Since: digit-8 0.1.0.
     */
    this(Socket socket) @trusted
    {
        this.socket = socket;
        try
        {
            socket.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO,
                    idleTimeoutSeconds.seconds);
        }
        catch (SocketException)
        {
            // Best effort: a socket the client already reset fails its
            // options and then its first read.
        }
    }

    /**
     * The socket descriptor.
     *
     * Returns: the descriptor.
     *
     * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
     * safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    socket_t handle() const @trusted nothrow @nogc
    {
        return socket.handle;
    }

    /**
     * Receive bytes (see `Connection.receive`).
     *
     * Params:
     *   buffer = where the bytes go.
     * Returns: the count; 0 at the end, on an error or a timeout.
     *
     * Errors: none. Side Effects: reads the socket. Complexity: O(n).
     * Thread Safety: one thread. Owner: AEC. Since: digit-8 0.1.0.
     */
    size_t receive(ubyte[] buffer) @trusted
    {
        while (true)
        {
            auto count = recv(socket.handle, buffer.ptr, buffer.length, 0);
            if (count < 0 && errno == EINTR)
            {
                continue;
            }
            return count > 0 ? count : 0;
        }
    }

    /**
     * Send all bytes (see `Connection.send`), without SIGPIPE.
     *
     * Params:
     *   bytes = the bytes.
     * Returns: true when every byte was sent.
     *
     * Errors: none. Side Effects: writes the socket. Complexity: O(n).
     * Thread Safety: one thread. Owner: AEC. Since: digit-8 0.1.0.
     */
    bool send(const(ubyte)[] bytes) @trusted
    {
        size_t offset = 0;
        while (offset < bytes.length)
        {
            auto count = posixSend(socket.handle, bytes.ptr + offset,
                    bytes.length - offset, MSG_NOSIGNAL);
            if (count < 0 && errno == EINTR)
            {
                continue;
            }
            if (count <= 0)
            {
                return false;
            }
            offset += count;
        }
        return true;
    }

    /**
     * Close with a linger: stop writing, discard input for up to
     * `lingerMilliseconds` or `lingerBytes`, then close the descriptor.
     *
     * Business_Justification: closing a socket with unread input makes the
     * kernel send a reset that can destroy the last reply (ADR-0026).
     *
     * Errors: none. Side Effects: closes the socket. Complexity: O(n).
     * Thread Safety: one thread. Owner: AEC. Since: digit-8 0.1.0.
     */
    void close() @trusted
    {
        socket.shutdown(SocketShutdown.SEND);
        try
        {
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO,
                    lingerMilliseconds.msecs);
        }
        catch (SocketException)
        {
            // The socket is already gone; the read below ends at once.
        }
        ubyte[4096] chunk;
        size_t discarded = 0;
        while (discarded <= lingerBytes)
        {
            auto count = receive(chunk[]);
            if (count == 0)
            {
                break;
            }
            discarded += count;
        }
        socket.close();
    }
}

/**
 * The HTTP server of the digit service.
 *
 * Description: an accept thread starts one thread per connection; the
 * contract is called under a mutex, so the store and the metrics are
 * never used concurrently. All threads are daemon threads: the process
 * ends when `digit8.service.run` returns, whatever they do. A druntime
 * thread keeps its stack until it is joined, so each connection thread
 * joins the one that ended before it (see `serve`).
 *
 * Business_Justification: the transport of the digit contract on port
 * 8080 (CLAUDE.md 6.1).
 *
 * Thread_Safety: safe; the shared state is guarded by `stateLock` and the
 * contract by `apiLock` (ADR-0030).
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
final class DigitServer
{
    /// The listening socket.
    private TcpSocket listener;
    /// The bound port.
    immutable ushort port;
    /// The contract.
    private Api api;
    /// Logger.
    private Logger log;
    /// Guards `connections`, `stopping`, `accepting` and `lastEnded`.
    private Mutex stateLock;
    /// Serialises calls to the contract.
    private Mutex apiLock;
    /// Open connections by descriptor, true while a request is served.
    private bool[socket_t] connections;
    /// True once the server stops.
    private bool stopping;
    /// True while the accept thread runs.
    private bool accepting = true;
    /// The connection thread that ended last and is not joined yet; `null`
    /// when none.
    private Thread lastEnded;

    /**
     * Bind a port on all IPv4 addresses and start serving.
     *
     * Description: the bind happens here, so a port in use fails the
     * start. Above `maxConnections` a new connection is closed at once.
     *
     * Business_Justification: port 8080 of every service (CLAUDE.md 6.1).
     *
     * Params:
     *   port = the TCP port, 1..65535 (0 picks a free port, for the tests).
     *   api = the contract that answers each request.
     *   log = the logger.
     * Throws: `ServerException` when the socket cannot be bound or the
     * accept thread cannot start.
     *
     * Side Effects: opens a socket; starts the accept thread.
     * Complexity: O(1). Thread Safety: call once. Owner: AEC.
     * Since: digit-8 0.1.0.
     *
     * Examples: `auto server = new DigitServer(8080, api, log);`
     *
     * See_Also: `stop`.
     */
    this(ushort port, Api api, Logger log) @trusted
    {
        this.api = api;
        this.log = log;
        stateLock = new Mutex();
        apiLock = new Mutex();
        try
        {
            listener = new TcpSocket();
            listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
            listener.bind(new InternetAddress(InternetAddress.ADDR_ANY, port));
            listener.listen(256);
            this.port = listener.localAddress.toPortString.to!ushort;
        }
        catch (SocketException error)
        {
            if (listener !is null)
            {
                listener.close();
            }
            throw new ServerException(error.msg);
        }
        if (!startThread(&acceptLoop))
        {
            listener.close();
            throw new ServerException("cannot start the accept thread");
        }
    }

    /**
     * Start a daemon thread with a small stack.
     *
     * Params:
     *   body_ = the code the thread runs.
     * Returns: true when the thread started.
     *
     * Errors: none (false when the system refuses a thread). Side Effects:
     * creates a thread. Complexity: O(1). Thread Safety: safe.
     * Owner: AEC. Since: digit-8 0.1.0.
     */
    private static bool startThread(void delegate() body_) @trusted
    {
        try
        {
            auto thread = new Thread(body_, threadStackSize);
            thread.isDaemon = true;
            thread.start();
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }

    /**
     * Whether the server stops.
     *
     * Returns: the flag, read under the state lock.
     *
     * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
     * safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    private bool isStopping() @trusted
    {
        stateLock.lock();
        scope (exit)
            stateLock.unlock();
        return stopping;
    }

    /**
     * Accept connections until the server stops.
     *
     * Description: each accepted connection gets its own thread; above
     * `maxConnections` it is closed at once. A failed accept (for example
     * too many open files) is logged and retried after 200 ms.
     *
     * Errors: none. Side Effects: accepts sockets; starts threads; logs.
     * Complexity: O(1) per connection. Thread Safety: the accept thread.
     * Owner: AEC. Since: digit-8 0.1.0.
     */
    private void acceptLoop() @trusted
    {
        while (true)
        {
            Socket client;
            string failure;
            try
            {
                client = listener.accept();
            }
            catch (SocketAcceptException error)
            {
                failure = error.msg;
            }
            if (isStopping())
            {
                if (client !is null)
                {
                    client.close();
                }
                break;
            }
            if (client is null)
            {
                log.write(Level.warn, "accept failed", failure);
                Thread.sleep(200.msecs);
                continue;
            }
            auto connection = new SocketConnection(client);
            bool admitted;
            {
                stateLock.lock();
                scope (exit)
                    stateLock.unlock();
                admitted = connections.length < maxConnections;
                if (admitted)
                {
                    connections[connection.handle] = false;
                }
            }
            if (!admitted)
            {
                log.write(Level.warn, "connection limit reached; connection closed",
                        maxConnections.to!string);
                client.close();
                continue;
            }
            if (!startThread(serveLater(connection)))
            {
                log.write(Level.warn, "cannot start a connection thread");
                forget(connection.handle);
                client.close();
            }
        }
        stateLock.lock();
        scope (exit)
            stateLock.unlock();
        accepting = false;
    }

    /**
     * The body of a connection thread.
     *
     * Description: a separate function, so that each delegate captures
     * its own connection; a delegate created in the accept loop would share
     * the loop's frame with every other iteration.
     *
     * Params:
     *   connection = the accepted connection.
     * Returns: a delegate that serves it.
     *
     * Errors: none. Side Effects: allocates the closure. Complexity: O(1).
     * Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    private void delegate() serveLater(SocketConnection connection) @safe
    {
        return () => serve(connection);
    }

    /**
     * Remove a connection from the open connections.
     *
     * Params:
     *   fd = its descriptor.
     *
     * Errors: none. Side Effects: updates the state. Complexity: O(1).
     * Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    private void forget(socket_t fd) @trusted
    {
        stateLock.lock();
        scope (exit)
            stateLock.unlock();
        connections.remove(fd);
    }

    /**
     * Serve one connection on its own thread, then close it.
     *
     * Description: at the end the thread records itself as `lastEnded`
     * and joins the thread recorded before it, which has ended or is
     * about to. A thread that is not joined keeps its stack mapped, so
     * without the join every connection would leave about 10 KiB of
     * resident memory behind until the garbage collector finalises its
     * `Thread` object; with it, at most one ended thread waits.
     *
     * Params:
     *   connection = the accepted connection.
     *
     * Errors: none. Side Effects: socket I/O; calls the contract under the
     * lock; updates the state; joins a thread. Complexity: that of the
     * requests. Thread Safety: one thread per connection. Owner: AEC.
     * Since: digit-8 0.1.0.
     */
    private void serve(SocketConnection connection) @trusted
    {
        auto fd = connection.handle;
        try
        {
            serveConnection(connection, (string method, string path) @trusted {
                apiLock.lock();
                scope (exit)
                    apiLock.unlock();
                return api.handle(method, path);
            }, () @trusted => isStopping(), (bool busy) @trusted {
                stateLock.lock();
                scope (exit)
                    stateLock.unlock();
                connections[fd] = busy;
            }, log);
        }
        catch (Exception error)
        {
            log.write(Level.error, "connection failed", error.msg);
        }
        forget(fd);
        connection.close();
        Thread previous;
        {
            stateLock.lock();
            scope (exit)
                stateLock.unlock();
            previous = lastEnded;
            lastEnded = Thread.getThis();
        }
        if (previous !is null)
        {
            previous.join(false);
        }
    }

    /**
     * Stop the server.
     *
     * Description: stops accepting, shuts the idle connections down and
     * waits up to `drainTimeoutSeconds` for running requests, which are
     * answered with Connection: close; then shuts down what is left.
     *
     * Business_Justification: graceful shutdown in at most 10 s
     * (CLAUDE.md 6.1).
     *
     * Errors: none. Side Effects: closes sockets. Complexity: O(c) in the
     * open connections. Thread Safety: call once. Owner: AEC.
     * Since: digit-8 0.1.0.
     *
     * See_Also: the constructor.
     */
    void stop() @trusted
    {
        socket_t[] idle;
        {
            stateLock.lock();
            scope (exit)
                stateLock.unlock();
            stopping = true;
            foreach (fd, busy; connections)
            {
                if (!busy)
                {
                    idle ~= fd;
                }
            }
        }
        shutdown(listener.handle, SHUT_RDWR);
        foreach (fd; idle)
        {
            shutdown(fd, SHUT_RD);
        }
        int waited = 0;
        while (waited < drainTimeoutSeconds * 1000 && !drained())
        {
            Thread.sleep(20.msecs);
            waited += 20;
        }
        {
            stateLock.lock();
            scope (exit)
                stateLock.unlock();
            foreach (fd; connections.byKey)
            {
                shutdown(fd, SHUT_RDWR);
            }
        }
        listener.close();
    }

    /**
     * Whether every connection is closed and the accept thread ended.
     *
     * Returns: true when nothing is left to wait for.
     *
     * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
     * safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    private bool drained() @trusted
    {
        stateLock.lock();
        scope (exit)
            stateLock.unlock();
        return connections.length == 0 && !accepting;
    }
}
