// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          lib/src/server.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Minimal HTTP/1.1 server on dart:io sockets: one
//                  asynchronous task per connection, persistent
//                  connections, bounded request heads and bodies, a
//                  connection cap and a graceful stop.
// Related Docs:    services/digit-5/README.md, contracts/http/digit.yaml,
//                  ADR-0027

/// HTTP/1.1 server of the digit service (RFC 9112), on the sockets of
/// `dart:io`.
///
/// The `HttpServer` of `dart:io` accepts request heads of up to 1 MiB and
/// cannot be configured lower; a dozen such heads made the service exceed
/// its 64 MB memory limit and be killed (ADR-0027). This library therefore
/// reads and writes HTTP/1.1 itself, as `digit-4` does in Lua (ADR-0026):
/// a request line, header fields, a body that is read and discarded
/// (Content-Length or chunked), persistent connections, HEAD without a
/// body and problem details for malformed requests.
///
/// The functions that do not touch a socket are public for the unit tests.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'api.dart';
import 'log.dart';
import 'trace.dart';

/// Largest request head (request line and header fields), in bytes; a
/// larger head is answered 431.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const int maxHead = 8192;

/// Largest request body read and discarded, in bytes; a larger one is
/// answered 413 without being read.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const int maxBody = 65536;

/// Most connections served at once; further ones are closed on accept.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const int maxConnections = 256;

/// Time a connection may stay silent, between requests or within one,
/// before it is closed.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const Duration idleTimeout = Duration(seconds: 10);

/// Time the server waits for running requests after a stop.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const Duration drainTimeout = Duration(seconds: 5);

/// Time unread input is still read and discarded after the last reply,
/// before the socket is destroyed.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const Duration lingerTimeout = Duration(milliseconds: 200);

/// Most bytes discarded after the last reply; a client still sending more
/// is cut off, so that a flood of oversized requests cannot make the
/// service read (and allocate) without bound while closing.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const int lingerBytes = 16384;

/// Reason phrases of the statuses the service sends.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const Map<int, String> reasons = {
  200: 'OK',
  400: 'Bad Request',
  404: 'Not Found',
  405: 'Method Not Allowed',
  413: 'Content Too Large',
  431: 'Request Header Fields Too Large',
  503: 'Service Unavailable',
};

/// Pattern of a request line: a token method, a target without spaces or
/// control characters and HTTP/1.0 or HTTP/1.1.
///
/// Owner: AEC. Since: digit-5 0.1.0.
final RegExp _requestLine = RegExp(
  r"^([!#$%&'*+\-.^_`|~0-9A-Za-z]+) ([^\x00-\x20\x7f]+) HTTP/1\.([01])$",
);

/// Pattern of a header field line: a token name, a colon and the value
/// with optional surrounding whitespace.
///
/// Owner: AEC. Since: digit-5 0.1.0.
final RegExp _headerLine = RegExp(
  r"^([!#$%&'*+\-.^_`|~0-9A-Za-z]+):[ \t]*(.*?)[ \t]*$",
);

/// A parsed request head.
///
/// Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
typedef RequestHead = ({
  String method,
  String target,
  String minor,
  Map<String, String> headers,
});

/// Parse a request line.
///
/// Description: the line must be method SP request-target SP
/// HTTP-version, where the method is a token (RFC 9110 tchar), the target
/// has no spaces or control characters and the version is HTTP/1.0 or
/// HTTP/1.1. The trailing CR LF must already be removed.
///
/// Business Justification: a malformed request is answered 400 instead of
/// being guessed at.
///
/// Parameters:
/// - [line]: request line without CR LF.
///
/// Returns: method, target and minor version ("0" or "1"), or null when
/// the line is invalid.
///
/// Errors: none (null for invalid input). Side Effects: none.
/// Complexity: O(n). Thread Safety: safe (pure).
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
///
/// Example: `parseRequestLine('GET /next HTTP/1.1')`.
///
/// See Also: [parseHeader].
({String method, String target, String minor})? parseRequestLine(String line) {
  final match = _requestLine.firstMatch(line);
  if (match == null) {
    return null;
  }
  return (method: match[1]!, target: match[2]!, minor: match[3]!);
}

/// Parse a header field line.
///
/// Description: name ":" OWS value OWS; the name is a token and is
/// returned in lower case. Obsolete line folding (a line starting with a
/// space) is rejected.
///
/// Business Justification: header fields decide the body length, the
/// persistence of the connection and the trace context.
///
/// Parameters:
/// - [line]: header line without CR LF.
///
/// Returns: the lower-case name and the value, or null when invalid.
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
/// safe (pure). Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `parseHeader('Content-Length: 5')`.
///
/// See Also: [parseRequestLine].
(String, String)? parseHeader(String line) {
  final match = _headerLine.firstMatch(line);
  if (match == null) {
    return null;
  }
  return (match[1]!.toLowerCase(), match[2]!);
}

/// Whether a comma-separated header value contains a token.
///
/// Business Justification: Connection: close may come with other tokens.
///
/// Parameters:
/// - [value]: header value, null when absent.
/// - [token]: lower-case token.
///
/// Returns: true when present (case-insensitive).
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
/// safe. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `_hasToken('keep-alive, Close', 'close') == true`.
///
/// See Also: [keepAlive].
bool _hasToken(String? value, String token) =>
    value != null &&
    value.toLowerCase().split(',').any((item) => item.trim() == token);

/// Whether the connection stays open after the reply.
///
/// Description: HTTP/1.1 keeps it unless the request says Connection:
/// close; HTTP/1.0 keeps it only with Connection: keep-alive.
///
/// Business Justification: callers reuse connections, which saves a TCP
/// handshake per digit call.
///
/// Parameters:
/// - [minor]: minor HTTP version, "0" or "1".
/// - [headers]: header fields by lower-case name.
///
/// Returns: true to keep the connection.
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
/// safe. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `keepAlive('1', {}) == true`.
///
/// See Also: [serveConnection].
bool keepAlive(String minor, Map<String, String> headers) => minor == '1'
    ? !_hasToken(headers['connection'], 'close')
    : _hasToken(headers['connection'], 'keep-alive');

/// Serialise a reply.
///
/// Description: status line, Date, Content-Type, Content-Length, Allow
/// when the reply has one and Connection: close when the connection ends;
/// the body is left out for HEAD.
///
/// Business Justification: one place produces the bytes of every answer.
///
/// Parameters:
/// - [reply]: the reply.
/// - [head]: true for a HEAD request.
/// - [close]: true when the connection is closed after the reply.
///
/// Returns: the response bytes.
///
/// Errors: none. Side Effects: reads the clock. Complexity: O(n) in the
/// body. Thread Safety: safe. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `formatReply(const Reply(200, jsonType, '{}'), false, false)`.
///
/// See Also: [Reply].
Uint8List formatReply(Reply reply, bool head, bool close) {
  final body = utf8.encode(reply.body);
  final text = StringBuffer()
    ..write('HTTP/1.1 ${reply.status} ${reasons[reply.status] ?? ''}\r\n')
    ..write('Date: ${HttpDate.format(DateTime.now())}\r\n')
    ..write('Content-Type: ${reply.contentType}\r\n')
    ..write('Content-Length: ${body.length}\r\n');
  if (reply.allow != null) {
    text.write('Allow: ${reply.allow}\r\n');
  }
  if (close) {
    text.write('Connection: close\r\n');
  }
  text.write('\r\n');
  return (BytesBuilder(copy: false)
        ..add(latin1.encode(text.toString()))
        ..add(head ? const <int>[] : body))
      .takeBytes();
}

/// Outcome of reading one line of a request.
///
/// Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
enum LineError {
  /// The input ended, failed or stayed silent past [idleTimeout].
  closed,

  /// The line is longer than the bytes still allowed.
  tooLarge,
}

/// Buffered reader of a connection's input.
///
/// Description: keeps the bytes received but not yet consumed; every wait
/// for more input times out after [idleTimeout]. After the end of the
/// input, a failure or a timeout, every read reports the end.
///
/// Business Justification: requests may arrive split across packets or
/// several in one packet (pipelining).
///
/// Thread Safety: one asynchronous task per connection.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
class InputReader {
  /// Read from [input].
  ///
  /// Parameters:
  /// - [input]: the connection's bytes (a socket or a test stream).
  /// - [timeout]: longest wait for more input.
  ///
  /// Errors: none. Side Effects: subscribes to [input] on the first read.
  /// Complexity: O(1). Thread Safety: one task. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `final reader = InputReader(socket);`
  ///
  /// See Also: [readLine].
  InputReader(Stream<List<int>> input, {this.timeout = idleTimeout})
    : _input = StreamIterator(input);

  /// The connection's bytes.
  final StreamIterator<List<int>> _input;

  /// Longest wait for more input.
  final Duration timeout;

  /// Bytes received; those before [_position] are consumed.
  Uint8List _buffer = Uint8List(0);

  /// Index of the first unconsumed byte of [_buffer].
  int _position = 0;

  /// True once the input ended, failed or timed out.
  bool _ended = false;

  /// Number of bytes received but not consumed.
  ///
  /// Returns: the count.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// one task. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `reader.available`.
  ///
  /// See Also: [_fill].
  int get available => _buffer.length - _position;

  /// Wait for the next chunk of input and append it to the buffer.
  ///
  /// Parameters:
  /// - [timeout]: longest wait.
  ///
  /// Returns: false at the end of the input, on a failure or a timeout.
  ///
  /// Errors: none. Side Effects: reads the input. Complexity: O(n) in the
  /// unconsumed bytes. Thread Safety: one task. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `if (!await _fill(timeout)) return null;`
  ///
  /// See Also: [readLine].
  Future<bool> _fill(Duration timeout) async {
    if (_ended) {
      return false;
    }
    try {
      if (await _input.moveNext().timeout(timeout)) {
        final chunk = _input.current;
        final rest = available;
        if (rest == 0 && chunk is Uint8List) {
          // Nothing left over: use the chunk as it is, without a copy.
          _buffer = chunk;
        } else {
          _buffer = Uint8List(rest + chunk.length)
            ..setRange(0, rest, _buffer, _position)
            ..setRange(rest, rest + chunk.length, chunk);
        }
        _position = 0;
        return true;
      }
    } on Object {
      // A timeout or a socket error ends the input like its end does.
    }
    _ended = true;
    return false;
  }

  /// Read one line.
  ///
  /// Description: lines end with LF, optionally preceded by CR, which is
  /// removed. [budget] is the number of bytes the line may take, its line
  /// ending included.
  ///
  /// Business Justification: bounds the memory a client can make the
  /// service hold.
  ///
  /// Parameters:
  /// - [budget]: bytes still allowed.
  ///
  /// Returns: the line (latin-1 decoded) and the bytes it took, or the
  /// error.
  ///
  /// Errors: none ([LineError] values). Side Effects: reads the input.
  /// Complexity: O(n). Thread Safety: one task. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `final (line, used, error) = await reader.readLine(8192);`
  ///
  /// See Also: [skip].
  Future<(String?, int, LineError?)> readLine(int budget) async {
    var searched = _position;
    while (true) {
      final end = _buffer.indexOf(10, searched);
      if (end >= 0) {
        final used = end - _position + 1;
        if (used > budget) {
          return (null, 0, LineError.tooLarge);
        }
        var stop = end;
        if (stop > _position && _buffer[stop - 1] == 13) {
          stop--;
        }
        final line = latin1.decode(
          Uint8List.sublistView(_buffer, _position, stop),
        );
        _position = end + 1;
        return (line, used, null);
      }
      if (available > budget) {
        return (null, 0, LineError.tooLarge);
      }
      // Every unconsumed byte was searched; after _fill they start at 0.
      final scanned = available;
      if (!await _fill(timeout)) {
        return (null, 0, LineError.closed);
      }
      searched = scanned;
    }
  }

  /// Read and discard [count] bytes.
  ///
  /// Business Justification: a body is consumed without being kept.
  ///
  /// Parameters:
  /// - [count]: bytes to skip.
  ///
  /// Returns: true when all bytes were read.
  ///
  /// Errors: none (false when the input ends early). Side Effects: reads
  /// the input. Complexity: O(n) time, O(chunk) memory. Thread Safety: one
  /// task. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `await reader.skip(10)`.
  ///
  /// See Also: [readLine].
  Future<bool> skip(int count) async {
    var left = count;
    while (true) {
      final take = left < available ? left : available;
      _position += take;
      left -= take;
      if (left == 0) {
        return true;
      }
      if (!await _fill(timeout)) {
        return false;
      }
    }
  }

  /// Discard input until it ends, [lingerTimeout] passes or more than
  /// [lingerBytes] were discarded.
  ///
  /// Business Justification: closing a socket with unread input makes the
  /// kernel send a reset that can destroy the last reply (ADR-0026).
  ///
  /// Returns: completes when done.
  ///
  /// Errors: none. Side Effects: reads the input. Complexity: O(n).
  /// Thread Safety: one task. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `await reader.linger();`
  ///
  /// See Also: [lingerTimeout].
  Future<void> linger() async {
    final deadline = DateTime.now().add(lingerTimeout);
    var discarded = 0;
    while (discarded <= lingerBytes) {
      discarded += available;
      _position = _buffer.length;
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero || !await _fill(left)) {
        return;
      }
    }
  }

  /// Stop reading the input.
  ///
  /// Returns: completes when the subscription is cancelled.
  ///
  /// Errors: none. Side Effects: cancels the subscription. Complexity:
  /// O(1). Thread Safety: one task. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `await reader.cancel();`
  ///
  /// See Also: [InputReader].
  Future<void> cancel() async {
    _ended = true;
    try {
      await _input.cancel();
    } on Object {
      // Already cancelled or failed: nothing left to release.
    }
  }
}

/// Read a request head.
///
/// Description: skips empty lines before the request line (RFC 9112,
/// 2.2), then reads header fields up to the empty line. Repeated fields
/// are joined with a comma.
///
/// Business Justification: the first stage of every request.
///
/// Parameters:
/// - [reader]: the connection's input.
///
/// Returns: the head, or the error status: null for a clean end (the
/// client closed or went silent before the request line was complete),
/// 400 for a malformed head or one cut short after the request line, 431
/// for a head above [maxHead].
///
/// Errors: none. Side Effects: reads the input. Complexity: O(n).
/// Thread Safety: one task. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `final (head, status) = await _readHead(reader);`
///
/// See Also: [_readBody].
Future<(RequestHead?, int?)> _readHead(InputReader reader) async {
  var budget = maxHead;
  String? line;
  do {
    final (text, used, error) = await reader.readLine(budget);
    if (text == null) {
      return (null, error == LineError.tooLarge ? 431 : null);
    }
    budget -= used;
    line = text;
  } while (line.isEmpty);
  final request = parseRequestLine(line);
  if (request == null) {
    return (null, 400);
  }
  final headers = <String, String>{};
  while (true) {
    final (text, used, error) = await reader.readLine(budget);
    if (text == null) {
      return (null, error == LineError.tooLarge ? 431 : 400);
    }
    budget -= used;
    if (text.isEmpty) {
      break;
    }
    final field = parseHeader(text);
    if (field == null) {
      return (null, 400);
    }
    final (name, value) = field;
    headers[name] = headers.containsKey(name)
        ? '${headers[name]}, $value'
        : value;
  }
  return (
    (
      method: request.method,
      target: request.target,
      minor: request.minor,
      headers: headers,
    ),
    null,
  );
}

/// Read and discard the request body.
///
/// Description: Content-Length bodies up to [maxBody] are skipped;
/// chunked bodies are skipped chunk by chunk with the same total limit
/// (trailer fields are read and ignored). A request with both
/// Content-Length and Transfer-Encoding, another transfer coding or an
/// invalid length is malformed (RFC 9112, 6.1 and 6.3).
///
/// Business Justification: the contract has no request bodies, but a body
/// sent anyway must not be mistaken for the next request.
///
/// Parameters:
/// - [reader]: the connection's input.
/// - [headers]: header fields by lower-case name.
///
/// Returns: null when the body was skipped, otherwise the error status:
/// 400 for a malformed or truncated body, 413 for one above [maxBody].
///
/// Errors: none. Side Effects: reads the input. Complexity: O(n).
/// Thread Safety: one task. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `final status = await _readBody(reader, head.headers);`
///
/// See Also: [_readHead].
Future<int?> _readBody(InputReader reader, Map<String, String> headers) async {
  final length = headers['content-length'];
  final coding = headers['transfer-encoding'];
  if (coding != null) {
    if (length != null || coding.toLowerCase() != 'chunked') {
      return 400;
    }
    var total = 0;
    while (true) {
      final (line, _, _) = await reader.readLine(maxHead);
      final size = line == null
          ? null
          : RegExp(r'^([0-9A-Fa-f]{1,8})[ \t]*(;.*)?$').firstMatch(line)?[1];
      if (size == null) {
        return 400;
      }
      final count = int.parse(size, radix: 16);
      total += count;
      if (total > maxBody) {
        return 413;
      }
      if (count == 0) {
        break;
      }
      if (!await reader.skip(count) || (await reader.readLine(2)).$1 != '') {
        return 400;
      }
    }
    while (true) {
      final (trailer, _, _) = await reader.readLine(maxHead);
      if (trailer == null) {
        return 400;
      }
      if (trailer.isEmpty) {
        return null;
      }
    }
  }
  if (length == null) {
    return null;
  }
  if (!RegExp(r'^\d{1,9}$').hasMatch(length)) {
    return 400;
  }
  final count = int.parse(length);
  if (count > maxBody) {
    return 413;
  }
  return await reader.skip(count) ? null : 400;
}

/// Serve the requests of one connection until it ends.
///
/// Description: reads a head, skips the body, asks [handler] for the
/// reply, logs it at debug level with the trace context and sends it;
/// repeats while the connection is persistent and [stopping] returns
/// false. Malformed requests are answered 400, 413 or 431 with problem
/// details and end the connection. [busy] is called with true when a
/// request starts and with false when it is answered.
///
/// Business Justification: the transport of the digit contract.
///
/// Parameters:
/// - [reader]: the connection's input.
/// - [output]: the connection's output (a socket or a test sink).
/// - [handler]: returns the reply for a method and a path.
/// - [stopping]: returns true once the server stops.
/// - [busy]: request start and end notifications.
/// - [log]: logger.
///
/// Returns: completes when the connection should be closed.
///
/// Errors: none (write failures end the connection). Side Effects: reads
/// and writes the connection; calls [handler]; logs. Complexity: O(n) per
/// request. Thread Safety: one task per connection; [handler] runs
/// synchronously. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `await serveConnection(reader, socket, api.handle, () => false, (_) {}, log);`
///
/// See Also: [Api.handle].
Future<void> serveConnection(
  InputReader reader,
  IOSink output,
  Reply Function(String method, String path) handler,
  bool Function() stopping,
  void Function(bool busy) busy,
  Logger log,
) async {
  while (true) {
    final (head, headStatus) = await _readHead(reader);
    if (head == null) {
      if (headStatus != null) {
        await _send(output, _rejection(headStatus), false, true);
        log.write(Level.debug, 'request rejected', detail: '$headStatus');
      }
      return;
    }
    busy(true);
    final bodyStatus = await _readBody(reader, head.headers);
    if (bodyStatus != null) {
      await _send(output, _rejection(bodyStatus), false, true);
      log.write(Level.debug, 'request rejected', detail: '$bodyStatus');
      return;
    }
    final query = head.target.indexOf('?');
    final path = query < 0 ? head.target : head.target.substring(0, query);
    final reply = handler(head.method, path);
    final keep = keepAlive(head.minor, head.headers) && !stopping();
    final trace = TraceContext.parse(head.headers['traceparent']);
    log.write(
      Level.debug,
      'request answered',
      traceId: trace?.traceId,
      spanId: trace?.spanId,
      detail: '${head.method} $path -> ${reply.status}',
    );
    final sent = await _send(output, reply, head.method == 'HEAD', !keep);
    busy(false);
    if (!sent || !keep) {
      return;
    }
  }
}

/// The problem details reply for a rejected request.
///
/// Parameters:
/// - [status]: 400, 413 or 431.
///
/// Returns: the reply.
///
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
/// safe. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `_rejection(431)`.
///
/// See Also: [problem].
Reply _rejection(int status) =>
    problem(status, reasons[status]!, 'the request is malformed or too large');

/// Send a reply and flush it.
///
/// Business Justification: the response leaves in one write, so no small
/// segment waits for a delayed acknowledgement.
///
/// Parameters:
/// - [output]: the connection's output.
/// - [reply]: the reply.
/// - [head]: true for a HEAD request (no body).
/// - [close]: true when the connection ends after the reply.
///
/// Returns: true when sent, false when the write failed.
///
/// Errors: none. Side Effects: writes the connection. Complexity: O(n).
/// Thread Safety: one task per connection. Owner: AEC.
/// Since: digit-5 0.1.0.
///
/// Example: `await _send(socket, reply, false, true)`.
///
/// See Also: [formatReply].
Future<bool> _send(IOSink output, Reply reply, bool head, bool close) async {
  try {
    output.add(formatReply(reply, head, close));
    await output.flush();
    return true;
  } on Object {
    return false;
  }
}

/// The HTTP server of the digit service.
///
/// Business Justification: the transport of the digit contract on port
/// 8080 (CLAUDE.md 6.1).
///
/// Thread Safety: one isolate. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
class DigitServer {
  /// Wrap a bound socket.
  ///
  /// Parameters:
  /// - [_listener]: the bound socket.
  /// - [_api]: the contract.
  /// - [_log]: logger.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: one isolate. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `DigitServer._(socket, api, log)`.
  ///
  /// See Also: [bind].
  DigitServer._(this._listener, this._api, this._log);

  /// The bound socket.
  final ServerSocket _listener;

  /// The contract.
  final Api _api;

  /// Logger.
  final Logger _log;

  /// Open connections, true while a request is being served.
  final Map<Socket, bool> _connections = {};

  /// Completes when the last connection has ended after a stop.
  Completer<void>? _drained;

  /// True once [stop] was called.
  bool _stopping = false;

  /// Port the server listens on (useful when bound to port 0 in tests).
  ///
  /// Returns: the port.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// one isolate. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `server.port`.
  ///
  /// See Also: [bind].
  int get port => _listener.port;

  /// Bind port [port] on all IPv4 addresses and start serving.
  ///
  /// Description: the bind happens here, so a port in use fails the
  /// start. Each accepted connection is served by its own asynchronous
  /// task; above [maxConnections] a new connection is closed at once.
  ///
  /// Business Justification: port 8080 of every service (CLAUDE.md 6.1).
  ///
  /// Parameters:
  /// - [port]: TCP port, 1..65535 (0 picks a free port, for the tests).
  /// - [api]: the contract that answers each request.
  /// - [log]: logger.
  ///
  /// Returns: the running server.
  ///
  /// Errors: [SocketException] when the port cannot be bound.
  /// Side Effects: opens a socket. Complexity: O(1). Thread Safety: call
  /// once. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `final server = await DigitServer.bind(8080, api, log);`
  ///
  /// See Also: [stop].
  static Future<DigitServer> bind(int port, Api api, Logger log) async {
    final listener = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    final server = DigitServer._(listener, api, log);
    listener.listen(
      server._accept,
      onError: (Object e) =>
          log.write(Level.warn, 'accept failed', detail: '$e'),
    );
    return server;
  }

  /// Accept one connection.
  ///
  /// Parameters:
  /// - [socket]: the accepted connection.
  ///
  /// Errors: none. Side Effects: starts serving the connection or closes
  /// it above [maxConnections]; logs. Complexity: O(1). Thread Safety:
  /// one isolate. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `listener.listen(server._accept)`.
  ///
  /// See Also: [_serve].
  void _accept(Socket socket) {
    if (_stopping || _connections.length >= maxConnections) {
      if (!_stopping) {
        _log.write(
          Level.warn,
          'connection limit reached; connection closed',
          detail: '$maxConnections',
        );
      }
      socket.destroy();
      return;
    }
    unawaited(_serve(socket));
  }

  /// Serve one connection until it ends, then close it.
  ///
  /// Description: the close lingers: the write side is closed first and
  /// input still arriving is discarded for up to [lingerTimeout], because
  /// closing a socket with unread input makes the kernel send a reset that
  /// can destroy the last reply.
  ///
  /// Parameters:
  /// - [socket]: the accepted connection.
  ///
  /// Returns: completes when the connection is closed.
  ///
  /// Errors: none. Side Effects: socket I/O; changes the connection
  /// table. Complexity: that of the requests. Thread Safety: one isolate.
  /// Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `unawaited(_serve(socket));`
  ///
  /// See Also: [serveConnection].
  Future<void> _serve(Socket socket) async {
    _connections[socket] = false;
    socket.setOption(SocketOption.tcpNoDelay, true);
    final reader = InputReader(socket);
    await serveConnection(
      reader,
      socket,
      _api.handle,
      () => _stopping,
      (busy) => _connections[socket] = busy,
      _log,
    );
    _connections.remove(socket);
    try {
      await socket.close().timeout(lingerTimeout);
    } on Object {
      // The peer does not read; the socket is destroyed below.
    }
    await reader.linger();
    await reader.cancel();
    socket.destroy();
    final drained = _drained;
    if (_connections.isEmpty && drained != null && !drained.isCompleted) {
      drained.complete();
    }
  }

  /// Stop the server.
  ///
  /// Description: stops accepting, shuts the idle connections down and
  /// waits up to [drainTimeout] for running requests, which are answered
  /// with Connection: close; then destroys what is left.
  ///
  /// Business Justification: graceful shutdown in at most 10 s
  /// (CLAUDE.md 6.1).
  ///
  /// Returns: completes when every connection is closed.
  ///
  /// Errors: none. Side Effects: closes sockets. Complexity: O(c) in the
  /// open connections. Thread Safety: one isolate. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `await server.stop();`
  ///
  /// See Also: [bind].
  Future<void> stop() async {
    _stopping = true;
    await _listener.close();
    if (_connections.isEmpty) {
      return;
    }
    final drained = _drained = Completer<void>();
    for (final MapEntry(key: socket, value: busy)
        in _connections.entries.toList()) {
      if (!busy) {
        socket.destroy();
      }
    }
    try {
      await drained.future.timeout(drainTimeout);
    } on TimeoutException {
      for (final socket in _connections.keys.toList()) {
        socket.destroy();
      }
    }
  }
}
