import 'package:aphrodite/auth/data/auth_api.dart';
import 'package:aphrodite/auth/data/auth_repository.dart';
import 'package:aphrodite/auth/data/token_store.dart';
import 'package:aphrodite/auth/models/auth_session.dart';
import 'package:aphrodite/core/network/network_client.dart';
import 'package:aphrodite/core/storage/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sign in stores only refresh token and keeps access token in memory',
      () async {
    final network = _FakeNetworkClient();
    final store = _MemorySecureStore();
    final session = InMemoryAuthSession();
    final repository = _repository(
      network: network,
      store: store,
      session: session,
    );

    await repository.signIn(
        login: 'example-user', password: 'example-password');

    expect(repository.accessToken, 'access-token-1');
    expect(session.accessToken, 'access-token-1');
    expect(store.values, {'auth.refresh_token': 'refresh-token-1'});
    expect(network.requests.map((request) => request.path), [
      '/v1/auth/challenges',
      '/v1/auth/challenges/challenge-1/verify',
      '/v1/auth/token',
    ]);
    expect(network.requests[1].data, containsPair('value', 'example-password'));
  });

  test('refresh rotates the stored refresh token', () async {
    final network = _FakeNetworkClient();
    final store = _MemorySecureStore()
      ..values['auth.refresh_token'] = 'refresh-token-1';
    final session = InMemoryAuthSession();
    final repository = _repository(
      network: network,
      store: store,
      session: session,
    );

    final accessToken = await repository.refreshAccessToken();

    expect(accessToken, 'access-token-2');
    expect(repository.accessToken, 'access-token-2');
    expect(session.accessToken, 'access-token-2');
    expect(store.values, {'auth.refresh_token': 'refresh-token-2'});
    expect(network.requests.single.data,
        containsPair('grant_type', 'refresh_token'));
  });

  test('failed refresh clears local credentials', () async {
    final network = _FakeNetworkClient(failRefresh: true);
    final store = _MemorySecureStore()
      ..values['auth.refresh_token'] = 'refresh-token-1';
    final session = InMemoryAuthSession()
      ..setAccessToken('previous-access-token');
    final repository = _repository(
      network: network,
      store: store,
      session: session,
    );

    await expectLater(repository.refreshAccessToken(), throwsStateError);

    expect(repository.accessToken, isNull);
    expect(session.accessToken, isNull);
    expect(store.values, isEmpty);
  });

  test('sign out clears local credentials even when remote logout fails',
      () async {
    final network = _FakeNetworkClient(failLogout: true);
    final store = _MemorySecureStore()
      ..values['auth.refresh_token'] = 'refresh-token-1';
    final session = InMemoryAuthSession()
      ..setAccessToken('previous-access-token');
    final repository = _repository(
      network: network,
      store: store,
      session: session,
    );

    await repository.signOut();

    expect(repository.accessToken, isNull);
    expect(session.accessToken, isNull);
    expect(store.values, isEmpty);
  });
}

ApiAuthRepository _repository({
  required _FakeNetworkClient network,
  required _MemorySecureStore store,
  required AuthSession session,
}) {
  return ApiAuthRepository(
    authApi: AuthApi(networkClient: network),
    deviceIdentityProvider: const _FakeDeviceIdentityProvider(),
    tokenStore: TokenStore(secureStore: store),
    authSession: session,
  );
}

class _FakeDeviceIdentityProvider implements DeviceIdentityProvider {
  const _FakeDeviceIdentityProvider();

  @override
  Future<DeviceIdentity> getOrCreate() async => const DeviceIdentity(
        deviceId: '00000000-0000-4000-8000-000000000001',
        deviceName: 'Aphrodite test device',
        platform: 'android',
        identityPublicKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      );
}

class _MemorySecureStore implements SecureStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeNetworkClient implements NetworkClient {
  _FakeNetworkClient({this.failRefresh = false, this.failLogout = false});

  final bool failRefresh;
  final bool failLogout;
  final List<_Request> requests = [];

  @override
  Future<Object?> get(String path, {Map<String, Object?>? queryParameters}) {
    throw UnimplementedError();
  }

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    requests.add(_Request(path: path, data: data));
    final payload = data! as Map<String, Object?>;
    if (path == '/v1/auth/challenges') {
      return _envelope({'challenge_id': 'challenge-1'});
    }
    if (path.endsWith('/verify')) {
      return _envelope({'authorization_code': 'authorization-code-1'});
    }
    if (path == '/v1/auth/token') {
      if (payload['grant_type'] == 'refresh_token') {
        if (failRefresh) throw StateError('refresh failed');
        return _envelope({
          'access_token': 'access-token-2',
          'refresh_token': 'refresh-token-2'
        });
      }
      return _envelope({
        'access_token': 'access-token-1',
        'refresh_token': 'refresh-token-1'
      });
    }
    if (path == '/v1/auth/logout') {
      if (failLogout) throw StateError('logout failed');
      return null;
    }
    throw StateError('unexpected path $path');
  }
}

Map<String, Object?> _envelope(Map<String, Object?> data) => {
      'request_id': 'request-1',
      'data': data,
      'meta': {'next_cursor': null},
    };

class _Request {
  const _Request({required this.path, required this.data});

  final String path;
  final Object? data;
}
