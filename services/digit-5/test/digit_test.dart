// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          test/digit_test.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Unit tests of the digit-5 service (package:test) against
//                  the real migrations: storage, contract, metrics, trace
//                  context, logging and the HTTP server.
// Related Docs:    services/digit-5/README.md, contracts/http/digit.yaml,
//                  ADR-0022, ADR-0027

/// Unit tests of the digit-5 service.
///
/// Run by `dart test` in the test stage of the Dockerfile, from the
/// service directory (the migrations are read from `migrations/`).
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:digit_service/digit_service.dart';
import 'package:test/test.dart';

/// Directory of the real migrations, relative to the service directory.
///
/// Owner: AEC. Since: digit-5 0.1.0.
const String migrations = 'migrations';

/// A logger that keeps its lines in memory, so that the test output stays
/// readable and the lines can be inspected.
///
/// Owner: AEC. Since: digit-5 0.1.0.
final StringBuffer logged = StringBuffer();

/// Logger of the tests, writing to [logged].
///
/// Owner: AEC. Since: digit-5 0.1.0.
final Logger log = Logger('digit-5', Level.debug, sink: logged);

/// Open an in-memory database migrated with the real migrations.
///
/// Business Justification: every test starts from the shipped schema and
/// seed.
///
/// Returns: the migrated store.
///
/// Errors: fails the test when the migration fails. Side Effects: none
/// outside the in-memory database. Complexity: O(1). Thread Safety: tests
/// run sequentially. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `final store = migrated();`
///
/// See Also: [Store.migrate].
Store migrated() {
  final store = Store.open(':memory:', log);
  expect(store.migrate(migrations), 1);
  return store;
}

/// Send one request to a running server and return status, headers and
/// body.
///
/// Business Justification: end-to-end tests of the transport.
///
/// Parameters:
/// - [port]: port of the server.
/// - [method]: HTTP method.
/// - [path]: request path.
/// - [body]: request body, null for none.
///
/// Returns: the response and its body text.
///
/// Errors: fails the test on I/O errors. Side Effects: one HTTP request.
/// Complexity: O(n). Thread Safety: tests run sequentially. Owner: AEC.
/// Since: digit-5 0.1.0.
///
/// Example: `final (response, text) = await call(port, 'GET', '/next');`
///
/// See Also: [DigitServer].
Future<(HttpClientResponse, String)> call(
  int port,
  String method,
  String path, {
  List<int>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.open(method, '127.0.0.1', port, path);
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close();
    return (response, await utf8.decodeStream(response));
  } finally {
    client.close();
  }
}

/// Run the unit tests.
///
/// Returns: nothing; package:test collects the groups.
///
/// Errors: none. Side Effects: in-memory databases, a server on a free
/// port. Complexity: O(1). Thread Safety: called once by the runner.
/// Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `dart test`.
///
/// See Also: [migrated], [call].
void main() {
  group('store', () {
    test('applies the migrations once', () {
      final store = migrated();
      expect(store.migrate(migrations), 0);
      expect(store.isApplied('0001_digit.sql'), isTrue);
    });

    test('reads the seeded row of digit 5', () {
      expect(migrated().read(), (digit: 5, value: 5, next: 6, carry: false));
    });

    test('fails for a missing migrations directory', () {
      final store = Store.open(':memory:', log);
      expect(
        () => store.migrate('/nonexistent'),
        throwsA(isA<StoreException>()),
      );
    });

    test('rolls back a failing migration and does not record it', () {
      final dir = Directory.systemTemp.createTempSync('digit5');
      File('${dir.path}/0001_bad.sql').writeAsStringSync(
        'CREATE TABLE t (x INTEGER); INSERT INTO nope VALUES (1);',
      );
      final store = Store.open(':memory:', log);
      expect(
        () => store.migrate(dir.path),
        throwsA(
          isA<StoreException>().having(
            (e) => e.message,
            'message',
            contains('0001_bad.sql failed'),
          ),
        ),
      );
      dir.deleteSync(recursive: true);
      expect(store.isApplied('0001_bad.sql'), isFalse);
      expect(
        () => store.execute('SELECT x FROM t;'),
        throwsA(isA<StoreException>()),
      );
    });

    test('rejects a table with more than one row', () {
      final store = migrated()
        ..execute('INSERT INTO digit VALUES (6, 6, 7, 0);');
      expect(store.read, throwsA(isA<StoreException>()));
    });
  });

  group('contract', () {
    late Store store;
    late Metrics metrics;
    late Api api;

    setUp(() {
      store = migrated();
      metrics = Metrics(5, '0.1.0');
      api = Api(store, 5, metrics, log);
    });

    test('answers GET /value and GET /next', () {
      final value = api.handle('GET', '/value');
      expect(value.status, 200);
      expect(value.contentType, jsonType);
      expect(value.body, '{"digit":5,"value":5}');
      expect(
        api.handle('GET', '/next').body,
        '{"digit":5,"next":6,"carry":false}',
      );
    });

    test('answers from the database, not from constants', () {
      store.execute('UPDATE digit SET next = 7, carry = 1;');
      expect(
        api.handle('GET', '/next').body,
        '{"digit":5,"next":7,"carry":true}',
      );
    });

    test('reports health from the database', () {
      final health = api.handle('GET', '/health');
      expect(health.status, 200);
      expect(health.body, '{"status":"ok","checks":{"database":"ok"}}');
    });

    test('answers 503 and counts an error when the row cannot be read', () {
      store.execute('DROP TABLE digit;');
      final reply = api.handle('GET', '/next');
      expect(reply.status, 503);
      expect(reply.contentType, problemType);
      expect(metrics.get(Endpoint.next, Outcome.error), 1);
      expect(api.handle('GET', '/health').status, 503);
    });

    test('answers 503 when the database holds another digit', () {
      final other = Api(store, 4, Metrics(4, '0.1.0'), log);
      expect(other.handle('GET', '/value').status, 503);
      expect(
        other.handle('GET', '/health').body,
        '{"status":"error","checks":{"database":"error"}}',
      );
    });

    test('answers 404 for an unknown path and 405 with Allow otherwise', () {
      final missing = api.handle('GET', '/nope');
      expect(missing.status, 404);
      expect(
        missing.body,
        '{"type":"about:blank","title":"Not Found","status":404,'
        '"detail":"the digit service has no such path"}',
      );
      final wrong = api.handle('POST', '/next');
      expect(wrong.status, 405);
      expect(wrong.allow, 'GET');
    });

    test('exposes the counters as Prometheus text', () {
      api.handle('GET', '/next');
      final text = api.handle('GET', '/metrics').body;
      expect(
        text,
        contains(
          'digit_requests_total{digit="5",endpoint="next",outcome="ok"} 1\n',
        ),
      );
      expect(
        text,
        contains(
          'digit_requests_total{digit="5",endpoint="value",outcome="error"} 0\n',
        ),
      );
      expect(text, contains('digit_build_info{digit="5",version="0.1.0"} 1\n'));
    });
  });

  group('trace and log', () {
    test('accepts a valid traceparent', () {
      final trace = TraceContext.parse(
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      );
      expect(trace?.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(trace?.spanId, '00f067aa0ba902b7');
    });

    test('rejects invalid traceparents', () {
      for (final header in [
        null,
        '',
        'ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        '00-00000000000000000000000000000000-00f067aa0ba902b7-01',
        '00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01',
        '00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01',
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-x',
      ]) {
        expect(TraceContext.parse(header), isNull, reason: '$header');
      }
    });

    test('escapes JSON, parses levels and writes the fields', () {
      expect(jsonEscape('a"b\\c\n\u0001'), r'a\"b\\c\n\u0001');
      expect(Level.parse('debug', Level.info), Level.debug);
      expect(Level.parse('loud', Level.info), Level.info);
      final sink = StringBuffer();
      Logger('digit-5', Level.info, sink: sink)
        ..write(Level.debug, 'hidden')
        ..write(Level.warn, 'shown', traceId: 'abc', detail: 'x');
      final line = jsonDecode(sink.toString()) as Map<String, Object?>;
      expect(line['level'], 'warn');
      expect(line['service'], 'digit-5');
      expect(line['taskId'], isNull);
      expect(line['traceId'], 'abc');
      expect(line['spanId'], isNull);
      expect(line['detail'], 'x');
      expect(
        line['ts'],
        matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$')),
      );
    });
  });

  group('transport', () {
    /// Serve scripted input through [serveConnection] and return what was
    /// sent.
    Future<String> serve(String input) async {
      final api = Api(migrated(), 5, Metrics(5, '0.1.0'), log);
      final sent = BytesBuilder();
      final controller = StreamController<List<int>>();
      final done = controller.stream.forEach(sent.add);
      final output = IOSink(controller);
      await serveConnection(
        InputReader(Stream.value(latin1.encode(input))),
        output,
        api.handle,
        () => false,
        (_) {},
        log,
      );
      await output.close();
      await done;
      return latin1.decode(sent.takeBytes());
    }

    /// Status codes of the responses in [out], in order.
    List<int> statuses(String out) => [
      for (final match in RegExp(r'HTTP/1\.1 (\d{3}) ').allMatches(out))
        int.parse(match[1]!),
    ];

    test('parses request lines and header fields', () {
      final line = parseRequestLine('GET /next?x=1 HTTP/1.1');
      expect(line?.method, 'GET');
      expect(line?.target, '/next?x=1');
      expect(line?.minor, '1');
      expect(parseRequestLine('GET /next HTTP/2.0'), isNull);
      expect(parseRequestLine('garbage'), isNull);
      expect(parseHeader('Content-Length:  5 '), ('content-length', '5'));
      expect(parseHeader(' folded'), isNull);
    });

    test('keeps HTTP/1.1 connections unless asked to close', () {
      expect(keepAlive('1', {}), isTrue);
      expect(keepAlive('1', {'connection': 'Close'}), isFalse);
      expect(keepAlive('0', {}), isFalse);
      expect(keepAlive('0', {'connection': 'keep-alive'}), isTrue);
    });

    test('serves pipelined requests on one connection', () async {
      final out = await serve(
        'GET /value HTTP/1.1\r\nHost: x\r\n\r\nGET /next?x=1 HTTP/1.1\r\n\r\n',
      );
      expect(statuses(out), [200, 200]);
      expect(out, contains('{"digit":5,"value":5}'));
      expect(out, contains('{"digit":5,"next":6,"carry":false}'));
      expect(out, isNot(contains('Connection: close')));
    });

    test('skips request bodies before the next request', () async {
      final out = await serve(
        'POST /value HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello'
        'GET /next HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n'
        '3\r\nabc\r\n0\r\n\r\nGET /value HTTP/1.1\r\n\r\n',
      );
      expect(statuses(out), [405, 200, 200]);
      expect(out, contains('Allow: GET\r\n'));
    });

    test('answers HEAD without a body and closes HTTP/1.0', () async {
      final out = await serve(
        'HEAD /next HTTP/1.0\r\n\r\nGET /value HTTP/1.1\r\n\r\n',
      );
      expect(statuses(out), [405]);
      expect(out, endsWith('Connection: close\r\n\r\n'));
    });

    test('rejects malformed and oversized requests and closes', () async {
      expect(
        statuses(await serve('garbage\r\n\r\nGET /value HTTP/1.1\r\n\r\n')),
        [400],
      );
      expect(
        statuses(await serve('GET /value HTTP/1.1\r\nbad header\r\n\r\n')),
        [400],
      );
      expect(
        statuses(
          await serve('GET /value HTTP/1.1\r\nContent-Length: x\r\n\r\n'),
        ),
        [400],
      );
      expect(
        statuses(
          await serve(
            'POST /value HTTP/1.1\r\nContent-Length: 3\r\n'
            'Transfer-Encoding: chunked\r\n\r\n',
          ),
        ),
        [400],
      );
      expect(
        statuses(
          await serve(
            'POST /value HTTP/1.1\r\nContent-Length: ${maxBody + 1}\r\n\r\n',
          ),
        ),
        [413],
      );
      final out = await serve(
        'GET /value HTTP/1.1\r\nX: ${'a' * maxHead}\r\n\r\n',
      );
      expect(statuses(out), [431]);
      expect(out, contains(problemType));
    });

    test('ends quietly when the client closes between requests', () async {
      expect(await serve(''), isEmpty);
      expect(await serve('\r\n'), isEmpty);
    });

    test('serves over TCP and stops', () async {
      final server = await DigitServer.bind(
        0,
        Api(migrated(), 5, Metrics(5, '0.1.0'), log),
        log,
      );
      final (response, text) = await call(server.port, 'GET', '/next');
      expect(response.statusCode, 200);
      expect(response.headers.value('content-type'), jsonType);
      expect(text, '{"digit":5,"next":6,"carry":false}');
      await server.stop();
    });
  });
}
