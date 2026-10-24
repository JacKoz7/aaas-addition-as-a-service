// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          src/digit8/http.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         HTTP/1.1 framing of the digit service: buffered line
//                  reading with a byte budget, request heads, bodies by
//                  Content-Length or chunked, reply formatting and the
//                  request loop of one connection.
// Related Docs:    services/digit-8/README.md, contracts/http/digit.yaml,
//                  RFC 9110, RFC 9112, ADR-0030

/**
 * HTTP/1.1 framing of the digit-8 service.
 *
 * The limits are those of the earlier digit services (ADR-0026 to
 * ADR-0029): heads up to 8 KiB (431 above), bodies up to 64 KiB read and
 * discarded (413 above), 400 for a malformed or ambiguous request.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8.http;

import digit8.api : problem, Reply;
import digit8.log : Level, Logger;
import digit8.trace : parseTraceparent;
import std.algorithm.comparison : min;
import std.algorithm.searching : all, countUntil;
import std.array : split;
import std.ascii : isDigit, isHexDigit;
import std.conv : to;
import std.datetime.systime : SysTime;
import std.format : format;
import std.string : strip;

/// Largest request head (request line and header fields), in bytes; a
/// larger head is answered 431.
enum size_t maxHead = 8192;

/// Largest request body read and discarded, in bytes; a larger one is
/// answered 413 without being read.
enum size_t maxBody = 65_536;

/// Most bytes asked from the connection in one receive.
private enum size_t receiveChunk = 16_384;

/**
 * The reason phrase of a status the service sends.
 *
 * Params:
 *   status = an HTTP status code.
 * Returns: the phrase; empty for a status the service never sends.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
string reason(int status) pure nothrow @safe @nogc
{
    switch (status)
    {
    case 200:
        return "OK";
    case 400:
        return "Bad Request";
    case 404:
        return "Not Found";
    case 405:
        return "Method Not Allowed";
    case 413:
        return "Content Too Large";
    case 431:
        return "Request Header Fields Too Large";
    case 503:
        return "Service Unavailable";
    default:
        return "";
    }
}

///
unittest
{
    assert(reason(431) == "Request Header Fields Too Large");
    assert(reason(299) == "");
}

/**
 * The two directions of a client connection, as the transport uses them.
 *
 * Business_Justification: the transport is tested with an in-memory double
 * instead of a socket.
 *
 * Thread_Safety: one thread per connection.
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
interface Connection
{
    /**
     * Receive bytes into a buffer.
     *
     * Params:
     *   buffer = where the bytes go; at most its length is received.
     * Returns: the number of bytes received; 0 at the end of the input, on
     * an error or after the receive timeout.
     *
     * Errors: none (0). Side Effects: reads the connection.
     * Complexity: O(n). Thread Safety: one thread. Owner: AEC.
     * Since: digit-8 0.1.0.
     */
    size_t receive(ubyte[] buffer) @safe;

    /**
     * Send all bytes.
     *
     * Params:
     *   bytes = the bytes.
     * Returns: true when every byte was sent.
     *
     * Errors: none (false). Side Effects: writes the connection.
     * Complexity: O(n). Thread Safety: one thread. Owner: AEC.
     * Since: digit-8 0.1.0.
     */
    bool send(const(ubyte)[] bytes) @safe;
}

/**
 * Outcome of reading one line of a request.
 *
 * Thread_Safety: a value type. Owner: AEC. Since: digit-8 0.1.0.
 */
enum LineStatus
{
    /// A line was read.
    ok,
    /// The input ended, failed or stayed silent past the receive timeout.
    closed,
    /// The line is longer than the bytes still allowed.
    tooLarge,
}

/**
 * One line read by `InputReader.readLine`.
 *
 * Thread_Safety: a value type. Owner: AEC. Since: digit-8 0.1.0.
 */
struct Line
{
    /// Whether a line was read, and why not otherwise.
    LineStatus status;
    /// The line without its line ending, ISO 8859-1 decoded; empty unless
    /// `status` is `ok`.
    string text;
    /// Bytes the line took, its line ending included.
    size_t used;
}

/**
 * Decode ISO 8859-1 bytes to a UTF-8 string.
 *
 * Description: every byte is one code point, so no input is invalid;
 * bytes above 0x7F become two-byte UTF-8 sequences.
 *
 * Business_Justification: HTTP field values are octets (RFC 9110, 5.5);
 * the service treats them as ISO 8859-1, like the earlier digit services.
 *
 * Params:
 *   bytes = the octets.
 * Returns: the text.
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
string latin1(const(ubyte)[] bytes) pure @safe
{
    if (bytes.all!(b => b < 0x80))
    {
        return (cast(const(char)[]) bytes).idup;
    }
    dchar[] text;
    foreach (b; bytes)
    {
        text ~= cast(dchar) b;
    }
    return text.to!string;
}

///
unittest
{
    assert(latin1(cast(const(ubyte)[]) "GET") == "GET");
    assert(latin1([0x63, 0xE9]) == "cé");
}

/**
 * Buffered reader of a connection's input.
 *
 * Description: keeps the bytes received but not yet consumed. After the
 * end of the input, a failure or a timeout, every read reports the end.
 *
 * Business_Justification: requests may arrive split across packets or
 * several in one packet (pipelining).
 *
 * Thread_Safety: one thread per connection.
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
final class InputReader
{
    /// The connection.
    private Connection connection;
    /// Bytes received; those before `position` are consumed.
    private ubyte[] buffer;
    /// Index of the first unconsumed byte of `buffer`.
    private size_t position;
    /// True once the input ended, failed or timed out.
    private bool ended;
    /// Receive buffer, reused for every receive.
    private ubyte[receiveChunk] chunk;

    /**
     * Read from a connection.
     *
     * Params:
     *   connection = the connection.
     *
     * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
     * one thread. Owner: AEC. Since: digit-8 0.1.0.
     */
    this(Connection connection) pure nothrow @safe
    {
        this.connection = connection;
    }

    /**
     * Number of bytes received but not consumed.
     *
     * Returns: the count.
     *
     * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
     * one thread. Owner: AEC. Since: digit-8 0.1.0.
     */
    size_t available() const pure nothrow @safe @nogc
    {
        return buffer.length - position;
    }

    /**
     * Receive the next chunk of input and append it to the buffer.
     *
     * Description: the consumed bytes are dropped first, so the buffer
     * never holds more than the unconsumed input and one chunk.
     *
     * Returns: false at the end of the input, on a failure or a timeout.
     *
     * Errors: none. Side Effects: reads the connection. Complexity: O(n)
     * in the unconsumed bytes. Thread Safety: one thread. Owner: AEC.
     * Since: digit-8 0.1.0.
     */
    private bool fill() @safe
    {
        if (ended)
        {
            return false;
        }
        auto count = connection.receive(chunk[]);
        if (count == 0)
        {
            ended = true;
            return false;
        }
        buffer = buffer[position .. $] ~ chunk[0 .. count];
        position = 0;
        return true;
    }

    /**
     * Read one line.
     *
     * Description: lines end with LF, optionally preceded by CR, which is
     * removed. `budget` is the number of bytes the line may take, its line
     * ending included.
     *
     * Business_Justification: bounds the memory a client can make the
     * service hold.
     *
     * Params:
     *   budget = the bytes still allowed.
     * Returns: the line, or the status `closed` or `tooLarge`.
     *
     * Errors: none (the status). Side Effects: reads the connection.
     * Complexity: O(n). Thread Safety: one thread. Owner: AEC.
     * Since: digit-8 0.1.0.
     */
    Line readLine(size_t budget) @safe
    {
        size_t searched = position;
        while (true)
        {
            auto offset = buffer[searched .. $].countUntil(cast(ubyte) '\n');
            if (offset >= 0)
            {
                auto end = searched + offset;
                auto used = end - position + 1;
                if (used > budget)
                {
                    return Line(LineStatus.tooLarge);
                }
                auto stop = end;
                if (stop > position && buffer[stop - 1] == '\r')
                {
                    stop--;
                }
                auto text = latin1(buffer[position .. stop]);
                position = end + 1;
                return Line(LineStatus.ok, text, used);
            }
            if (available > budget)
            {
                return Line(LineStatus.tooLarge);
            }
            auto scanned = available;
            if (!fill())
            {
                return Line(LineStatus.closed);
            }
            searched = scanned;
        }
    }

    /**
     * Read and discard bytes.
     *
     * Params:
     *   count = the bytes to skip.
     * Returns: true when all bytes were read.
     *
     * Errors: none (false when the input ends early). Side Effects: reads
     * the connection. Complexity: O(n). Thread Safety: one thread.
     * Owner: AEC. Since: digit-8 0.1.0.
     */
    bool skip(size_t count) @safe
    {
        auto left = count;
        while (true)
        {
            auto take = min(left, available);
            position += take;
            left -= take;
            if (left == 0)
            {
                return true;
            }
            if (!fill())
            {
                return false;
            }
        }
    }
}

/**
 * A parsed request head.
 *
 * Thread_Safety: a value type. Owner: Arithmetic Excellence Center (AEC).
 * Since: digit-8 0.1.0.
 */
struct RequestHead
{
    /// The method, as received.
    string method;
    /// The request target (path and query).
    string target;
    /// The minor HTTP version, "0" or "1".
    string minor;
    /// Header fields by lower-case name; repeated fields joined by commas.
    string[string] headers;
}

/**
 * Whether a character is an RFC 9110 token character (tchar).
 *
 * Params:
 *   c = the character.
 * Returns: true for a token character.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
bool isToken(dchar c) pure nothrow @safe @nogc
{
    import std.algorithm.searching : canFind;
    import std.ascii : isAlphaNum;

    return isAlphaNum(c) || "!#$%&'*+-.^_`|~"d.canFind(c);
}

///
unittest
{
    assert(isToken('G') && isToken('~'));
    assert(!isToken(' ') && !isToken(':') && !isToken('é'));
}

/**
 * Parse a request line.
 *
 * Description: the line must be method SP request-target SP HTTP-version,
 * where the method is a token (RFC 9110 tchar), the target has no spaces
 * or control characters and the version is HTTP/1.0 or HTTP/1.1. The
 * trailing CR LF must already be removed.
 *
 * Business_Justification: a malformed request is answered 400 instead of
 * being guessed at.
 *
 * Params:
 *   line = the request line without CR LF.
 *   head = receives the method, the target and the minor version.
 * Returns: true when the line is valid.
 *
 * Errors: none (false). Side Effects: none. Complexity: O(n).
 * Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
 * Since: digit-8 0.1.0.
 *
 * See_Also: `parseHeader`.
 */
bool parseRequestLine(string line, out RequestHead head) pure @safe
{
    auto parts = line.split(" ");
    if (parts.length != 3 || parts[0].length == 0 || !parts[0].all!isToken
            || parts[1].length == 0 || !parts[1].all!(c => c > ' ' && c != 0x7F)
            || (parts[2] != "HTTP/1.0" && parts[2] != "HTTP/1.1"))
    {
        return false;
    }
    head.method = parts[0];
    head.target = parts[1];
    head.minor = parts[2][$ - 1 .. $];
    return true;
}

///
unittest
{
    RequestHead head;
    assert(parseRequestLine("GET /next?x=1 HTTP/1.1", head));
    assert(head.method == "GET" && head.target == "/next?x=1" && head.minor == "1");
    assert(!parseRequestLine("GET  /next HTTP/1.1", head));
    assert(!parseRequestLine("GET /next HTTP/2.0", head));
    assert(!parseRequestLine("PRI * HTTP/2.0", head));
}

/**
 * Parse a header field line.
 *
 * Description: name ":" OWS value OWS; the name is a token and is
 * returned in lower case. Obsolete line folding (a line starting with a
 * space) is rejected, because a space is not a token character.
 *
 * Business_Justification: header fields decide the body length, the
 * persistence of the connection and the trace context.
 *
 * Params:
 *   line = the header line without CR LF.
 *   name = receives the lower-case name.
 *   value = receives the value without surrounding spaces and tabs.
 * Returns: true when the line is valid.
 *
 * Errors: none (false). Side Effects: none. Complexity: O(n).
 * Thread Safety: pure. Owner: AEC. Since: digit-8 0.1.0.
 */
bool parseHeader(string line, out string name, out string value) pure @safe
{
    import std.string : indexOf;
    import std.uni : toLower;

    auto colon = line.indexOf(':');
    if (colon <= 0 || !line[0 .. colon].all!isToken)
    {
        return false;
    }
    name = line[0 .. colon].toLower;
    value = line[colon + 1 .. $].strip(" \t");
    return true;
}

///
unittest
{
    string name, value;
    assert(parseHeader("Content-Length: \t5 ", name, value));
    assert(name == "content-length" && value == "5");
    assert(!parseHeader(" folded: x", name, value));
    assert(!parseHeader(": x", name, value));
}

/**
 * Whether a comma-separated header value contains a token.
 *
 * Params:
 *   value = the header value; `null` when absent.
 *   token = the lower-case token.
 * Returns: true when present (case-insensitive).
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
bool hasToken(string value, string token) pure @safe
{
    import std.algorithm.iteration : map;
    import std.algorithm.searching : canFind;
    import std.uni : asLowerCase;

    if (value is null)
    {
        return false;
    }
    return value.asLowerCase.to!string.split(",").map!(part => part.strip(" \t")).canFind(token);
}

///
unittest
{
    assert(hasToken("keep-alive, Close", "close"));
    assert(!hasToken("closed", "close"));
    assert(!hasToken(null, "close"));
}

/**
 * Whether the connection stays open after the reply.
 *
 * Description: HTTP/1.1 keeps it unless the request says Connection:
 * close; HTTP/1.0 keeps it only with Connection: keep-alive.
 *
 * Business_Justification: callers reuse connections, which saves a TCP
 * handshake per digit call.
 *
 * Params:
 *   minor = the minor HTTP version, "0" or "1".
 *   headers = the header fields by lower-case name.
 * Returns: true to keep the connection.
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
bool keepAlive(string minor, const string[string] headers) pure @safe
{
    auto connection = "connection" in headers;
    auto value = connection is null ? null : *connection;
    return minor == "1" ? !hasToken(value, "close") : hasToken(value, "keep-alive");
}

///
unittest
{
    assert(keepAlive("1", null));
    assert(!keepAlive("1", ["connection": "close"]));
    assert(!keepAlive("0", null));
    assert(keepAlive("0", ["connection": "Keep-Alive"]));
}

/**
 * The current date in the IMF-fixdate format of the Date header.
 *
 * Returns: for example `Sat, 24 Oct 2026 12:00:00 GMT`.
 *
 * Errors: none. Side Effects: reads the clock. Complexity: O(1).
 * Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
 */
string httpDate() @safe
{
    import std.datetime.systime : Clock;
    import std.datetime.timezone : UTC;

    return imfFixdate(Clock.currTime(UTC()));
}

/**
 * Format a time in the IMF-fixdate format (RFC 9110, 5.6.7).
 *
 * Params:
 *   time = any time; it is converted to UTC.
 * Returns: for example `Sat, 24 Oct 2026 12:00:00 GMT`.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
string imfFixdate(SysTime time) @safe
{
    static immutable days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    static immutable months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
        "Nov", "Dec"
    ];
    auto utc = time.toUTC();
    return format!"%s, %02d %s %04d %02d:%02d:%02d GMT"(days[utc.dayOfWeek],
            utc.day, months[utc.month - 1], utc.year, utc.hour, utc.minute, utc.second);
}

///
unittest
{
    import std.datetime.date : DateTime;
    import std.datetime.timezone : UTC;

    assert(imfFixdate(SysTime(DateTime(2026, 10, 24, 12, 0, 5),
            UTC())) == "Sat, 24 Oct 2026 12:00:05 GMT");
}

/**
 * Serialise a reply.
 *
 * Description: status line, Date, Content-Type, Content-Length, Allow when
 * the reply has one and Connection: close when the connection ends; the
 * body is left out for HEAD.
 *
 * Business_Justification: one place produces the bytes of every answer.
 *
 * Params:
 *   reply = the reply.
 *   head = true for a HEAD request.
 *   close = true when the connection is closed after the reply.
 * Returns: the response bytes.
 *
 * Errors: none. Side Effects: reads the clock. Complexity: O(n) in the
 * body. Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
 */
immutable(ubyte)[] formatReply(Reply reply, bool head, bool close) @safe
{
    auto text = format!"HTTP/1.1 %d %s\r\nDate: %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"(
            reply.status, reason(reply.status), httpDate(), reply.contentType, reply.body.length);
    if (reply.allow !is null)
    {
        text ~= "Allow: " ~ reply.allow ~ "\r\n";
    }
    if (close)
    {
        text ~= "Connection: close\r\n";
    }
    text ~= "\r\n";
    if (!head)
    {
        text ~= reply.body;
    }
    return cast(immutable(ubyte)[]) text;
}

///
unittest
{
    import std.algorithm.searching : endsWith, startsWith;

    auto bytes = cast(string) formatReply(Reply(405,
            "application/problem+json", "{}", "GET"), false, true);
    assert(bytes.startsWith("HTTP/1.1 405 Method Not Allowed\r\nDate: "));
    assert(bytes.endsWith("Content-Length: 2\r\nAllow: GET\r\nConnection: close\r\n\r\n{}"));
    auto headOnly = cast(string) formatReply(Reply(200, "application/json", "{}"), true, false);
    assert(headOnly.endsWith("Content-Length: 2\r\n\r\n"));
}

/**
 * The result of `readHead`.
 *
 * Thread_Safety: a value type. Owner: AEC. Since: digit-8 0.1.0.
 */
struct HeadResult
{
    /// The head; valid only when `status` is 0 and `ended` is false.
    RequestHead head;
    /// 0 for a head, otherwise the error status (400 or 431).
    int status;
    /// True for a clean end: the client closed or went silent before the
    /// request line was complete.
    bool ended;
}

/**
 * Read a request head.
 *
 * Description: skips empty lines before the request line (RFC 9112, 2.2),
 * then reads header fields up to the empty line. Repeated fields are
 * joined with a comma.
 *
 * Params:
 *   reader = the connection's input.
 * Returns: the head, a clean end, or the error status: 400 for a
 * malformed head or one cut short after the request line, 431 for a head
 * above `maxHead`.
 *
 * Errors: none (the status). Side Effects: reads the connection.
 * Complexity: O(n). Thread Safety: one thread. Owner: AEC.
 * Since: digit-8 0.1.0.
 */
HeadResult readHead(InputReader reader) @safe
{
    size_t budget = maxHead;
    Line line;
    do
    {
        line = reader.readLine(budget);
        if (line.status == LineStatus.tooLarge)
        {
            return HeadResult(RequestHead.init, 431);
        }
        if (line.status == LineStatus.closed)
        {
            return HeadResult(RequestHead.init, 0, true);
        }
        budget -= line.used;
    }
    while (line.text.length == 0);
    RequestHead head;
    if (!parseRequestLine(line.text, head))
    {
        return HeadResult(RequestHead.init, 400);
    }
    while (true)
    {
        line = reader.readLine(budget);
        if (line.status != LineStatus.ok)
        {
            return HeadResult(RequestHead.init, line.status == LineStatus.tooLarge ? 431 : 400);
        }
        budget -= line.used;
        if (line.text.length == 0)
        {
            return HeadResult(head);
        }
        string name, value;
        if (!parseHeader(line.text, name, value))
        {
            return HeadResult(RequestHead.init, 400);
        }
        auto existing = name in head.headers;
        head.headers[name] = existing is null ? value : *existing ~ ", " ~ value;
    }
}

/**
 * Read and discard the request body.
 *
 * Description: Content-Length bodies up to `maxBody` are skipped; chunked
 * bodies are skipped chunk by chunk with the same total limit (trailer
 * fields are read and ignored). A request with both Content-Length and
 * Transfer-Encoding, another transfer coding or an invalid length is
 * malformed (RFC 9112, 6.1 and 6.3).
 *
 * Business_Justification: the contract has no request bodies, but a body
 * sent anyway must not be mistaken for the next request.
 *
 * Params:
 *   reader = the connection's input.
 *   headers = the header fields by lower-case name.
 * Returns: 0 when the body was skipped, otherwise the error status: 400
 * for a malformed or truncated body, 413 for one above `maxBody`.
 *
 * Errors: none (the status). Side Effects: reads the connection.
 * Complexity: O(n). Thread Safety: one thread. Owner: AEC.
 * Since: digit-8 0.1.0.
 */
int readBody(InputReader reader, const string[string] headers) @safe
{
    auto length = "content-length" in headers;
    auto coding = "transfer-encoding" in headers;
    if (coding !is null)
    {
        import std.uni : sicmp;

        if (length !is null || sicmp(*coding, "chunked") != 0)
        {
            return 400;
        }
        size_t total = 0;
        while (true)
        {
            auto line = reader.readLine(maxHead);
            if (line.status != LineStatus.ok)
            {
                return 400;
            }
            auto digits = line.text.countUntil!(c => !isHexDigit(c));
            auto size = digits < 0 ? line.text : line.text[0 .. digits];
            if (size.length < 1 || size.length > 8)
            {
                return 400;
            }
            auto count = size.to!size_t(16);
            total += count;
            if (total > maxBody)
            {
                return 413;
            }
            if (count == 0)
            {
                break;
            }
            if (!reader.skip(count))
            {
                return 400;
            }
            auto end = reader.readLine(2);
            if (end.status != LineStatus.ok || end.text.length != 0)
            {
                return 400;
            }
        }
        while (true)
        {
            auto trailer = reader.readLine(maxHead);
            if (trailer.status != LineStatus.ok)
            {
                return 400;
            }
            if (trailer.text.length == 0)
            {
                return 0;
            }
        }
    }
    if (length is null)
    {
        return 0;
    }
    if ((*length).length < 1 || (*length).length > 9 || !(*length).all!isDigit)
    {
        return 400;
    }
    auto count = (*length).to!size_t;
    if (count > maxBody)
    {
        return 413;
    }
    return reader.skip(count) ? 0 : 400;
}

/**
 * The problem details reply for a rejected request.
 *
 * Params:
 *   status = 400, 413 or 431.
 * Returns: the reply.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
Reply rejection(int status) pure @safe
{
    return problem(status, reason(status), "the request is malformed or too large");
}

///
unittest
{
    assert(rejection(413).status == 413);
    assert(rejection(413).allow is null);
}

/**
 * Serve the requests of one connection until it ends.
 *
 * Description: reads a head, skips the body, asks `handler` for the reply,
 * logs it at debug level with the trace context and sends it; repeats
 * while the connection is persistent and `stopping` returns false.
 * Malformed requests are answered 400, 413 or 431 with problem details and
 * end the connection. `busy` is called with true when a request starts and
 * with false when it is answered.
 *
 * Business_Justification: the transport of the digit contract.
 *
 * Params:
 *   connection = the connection.
 *   handler = returns the reply for a method and a path.
 *   stopping = returns true once the server stops.
 *   busy = request start and end notifications.
 *   log = the logger.
 *
 * Errors: none (write failures end the connection). Side Effects: reads
 * and writes the connection; calls `handler`; logs. Complexity: O(n) per
 * request. Thread Safety: one thread per connection. Owner: AEC.
 * Since: digit-8 0.1.0.
 *
 * See_Also: `digit8.api.Api.handle`.
 */
void serveConnection(Connection connection, scope Reply delegate(string,
        string) @safe handler, scope bool delegate() @safe stopping,
        scope void delegate(bool) @safe busy, Logger log) @safe
{
    auto reader = new InputReader(connection);
    while (true)
    {
        auto result = readHead(reader);
        if (result.ended)
        {
            return;
        }
        if (result.status != 0)
        {
            connection.send(formatReply(rejection(result.status), false, true));
            log.write(Level.debug_, "request rejected", result.status.to!string);
            return;
        }
        auto head = result.head;
        busy(true);
        auto bodyStatus = readBody(reader, head.headers);
        if (bodyStatus != 0)
        {
            connection.send(formatReply(rejection(bodyStatus), false, true));
            log.write(Level.debug_, "request rejected", bodyStatus.to!string);
            return;
        }
        auto query = head.target.countUntil('?');
        auto path = query < 0 ? head.target : head.target[0 .. query];
        auto reply = handler(head.method, path);
        auto keep = keepAlive(head.minor, head.headers) && !stopping();
        auto traceparent = "traceparent" in head.headers;
        auto trace = parseTraceparent(traceparent is null ? null : *traceparent);
        auto detail = format!"%s %s -> %d"(head.method, path, reply.status);
        if (trace.isNull)
        {
            log.write(Level.debug_, "request answered", detail);
        }
        else
        {
            log.write(Level.debug_, "request answered", detail,
                    trace.get.traceId, trace.get.spanId);
        }
        auto sent = connection.send(formatReply(reply, head.method == "HEAD", !keep));
        busy(false);
        if (!sent || !keep)
        {
            return;
        }
    }
}
