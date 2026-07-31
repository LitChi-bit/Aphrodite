import 'dart:async';
import 'dart:typed_data';

import 'package:aphrodite/auth/models/auth_session.dart';
import 'package:aphrodite/core/network/access_token_provider.dart';
import 'package:aphrodite/core/network/dio_network_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not attach Authorization when the session is empty', () async {
    final session = InMemoryAuthSession();
    final headers = await _requestHeaders(session);

    expect(headers.containsKey('Authorization'), isFalse);
  });

  test('dynamically attaches the current Bearer access token', () async {
    final session = InMemoryAuthSession()..setAccessToken('access-token-1');

    expect(await _requestHeaders(session),
        containsPair('Authorization', 'Bearer access-token-1'));

    session.setAccessToken('access-token-2');
    expect(await _requestHeaders(session),
        containsPair('Authorization', 'Bearer access-token-2'));

    session.clear();
    expect(
        (await _requestHeaders(session)).containsKey('Authorization'), isFalse);
  });

  test('refreshes once and retries a protected request after a 401', () async {
    final session = InMemoryAuthSession()..setAccessToken('expired-token');
    final refresher = _FakeRefresher(session, 'fresh-token');
    session.setRefresher(refresher);
    final attempts = <String>[];
    final client = _clientWithAdapter(
      session: session,
      responseFor: (options) {
        attempts.add(options.headers['Authorization'] as String? ?? 'none');
        return options.extra['aphrodite.auth.retried'] == true ? 200 : 401;
      },
    );

    await client.get('/v1/devices');

    expect(refresher.calls, 1);
    expect(attempts, ['Bearer expired-token', 'Bearer fresh-token']);
  });

  test('concurrent 401 responses share one refresh operation', () async {
    final session = InMemoryAuthSession()..setAccessToken('expired-token');
    final refresher = _ControlledRefresher(session);
    session.setRefresher(refresher);
    var initialRequests = 0;
    final initialUnauthorized = Completer<int>();
    final client = _clientWithAdapter(
      session: session,
      responseFor: (options) async {
        if (options.extra['aphrodite.auth.retried'] == true) return 200;
        initialRequests += 1;
        if (initialRequests == 2 && !initialUnauthorized.isCompleted) {
          initialUnauthorized.complete(401);
        }
        return initialUnauthorized.future;
      },
    );

    final first = client.get('/v1/devices');
    final second = client.get('/v1/conversations');
    await refresher.started;
    expect(refresher.calls, 1);

    refresher.complete('fresh-token');
    await Future.wait([first, second]);

    expect(refresher.calls, 1);
  });

  test('does not refresh auth endpoints or retry a second 401', () async {
    final session = InMemoryAuthSession()..setAccessToken('expired-token');
    final refresher = _FakeRefresher(session, 'fresh-token');
    session.setRefresher(refresher);
    final client = _clientWithAdapter(
      session: session,
      responseFor: (_) => 401,
    );

    await expectLater(client.post('/v1/auth/token'), throwsA(isA<Object>()));
    await expectLater(client.get('/v1/devices'), throwsA(isA<Object>()));

    expect(refresher.calls, 1);
  });
}

DioNetworkClient _clientWithAdapter({
  required InMemoryAuthSession session,
  required FutureOr<int> Function(RequestOptions options) responseFor,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
  dio.httpClientAdapter = _StatusCodeAdapter(responseFor);
  return DioNetworkClient(
    baseUrl: 'https://test.invalid',
    accessTokenProvider: session,
    accessTokenRefresher: () => session.refresher,
    dio: dio,
  );
}

Future<Map<String, dynamic>> _requestHeaders(
    InMemoryAuthSession session) async {
  late Map<String, dynamic> capturedHeaders;
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
  dio.httpClientAdapter = _StatusCodeAdapter((options) {
    capturedHeaders = Map<String, dynamic>.from(options.headers);
    return 200;
  });
  final client = DioNetworkClient(
    baseUrl: 'https://test.invalid',
    accessTokenProvider: session,
    dio: dio,
  );

  await client.get('/v1/devices');
  return capturedHeaders;
}

final class _StatusCodeAdapter implements HttpClientAdapter {
  _StatusCodeAdapter(this._responseFor);

  final FutureOr<int> Function(RequestOptions options) _responseFor;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        '{}',
        await _responseFor(options),
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
}

final class _FakeRefresher implements AccessTokenRefresher {
  _FakeRefresher(this.session, this.nextAccessToken);

  final InMemoryAuthSession session;
  final String nextAccessToken;
  int calls = 0;

  @override
  Future<String?> refreshAccessToken() async {
    calls += 1;
    session.setAccessToken(nextAccessToken);
    return nextAccessToken;
  }
}

final class _ControlledRefresher implements AccessTokenRefresher {
  _ControlledRefresher(this.session);

  final InMemoryAuthSession session;
  final Completer<String?> _completer = Completer<String?>();
  final Completer<void> _started = Completer<void>();
  int calls = 0;

  Future<void> get started => _started.future;

  @override
  Future<String?> refreshAccessToken() {
    calls += 1;
    if (!_started.isCompleted) _started.complete();
    return _completer.future;
  }

  void complete(String accessToken) {
    session.setAccessToken(accessToken);
    _completer.complete(accessToken);
  }
}
