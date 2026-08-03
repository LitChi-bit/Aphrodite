import 'package:aphrodite/auth/data/device_api.dart';
import 'package:aphrodite/core/network/network_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the device list envelope strictly', () async {
    final client = _FakeNetworkClient(
      getResponse: _envelope([
        {
          'id': 'device-1',
          'name': 'Aphrodite Android',
          'platform': 'android',
          'current': true,
          'revoked': false,
          'last_seen_at': '2026-07-31T04:00:00Z',
          'created_at': '2026-07-01T04:00:00Z',
        },
      ]),
    );

    final devices = await DeviceApi(networkClient: client).listDevices();

    expect(devices, hasLength(1));
    expect(devices.single.id, 'device-1');
    expect(devices.single.current, isTrue);
    expect(devices.single.createdAt, DateTime.utc(2026, 7, 1, 4));
    expect(client.lastPath, '/v1/devices');
  });

  test('allows nullable last_seen_at', () async {
    final client = _FakeNetworkClient(
      getResponse: _envelope([
        {
          'id': 'device-2',
          'name': 'Aphrodite iOS',
          'platform': 'ios',
          'current': false,
          'revoked': true,
          'last_seen_at': null,
          'created_at': '2026-07-01T04:00:00Z',
        },
      ]),
    );

    final devices = await DeviceApi(networkClient: client).listDevices();

    expect(devices.single.lastSeenAt, isNull);
    expect(devices.single.revoked, isTrue);
  });

  test('rejects malformed device data', () async {
    final client = _FakeNetworkClient(
      getResponse: _envelope([
        {
          'id': 'device-1',
          'name': 'Aphrodite Android',
          'platform': 'android',
          'current': 'true',
          'revoked': false,
          'last_seen_at': null,
          'created_at': '2026-07-01T04:00:00Z',
        },
      ]),
    );

    await expectLater(
      DeviceApi(networkClient: client).listDevices(),
      throwsA(isA<FormatException>()),
    );
  });

  test('revokes a trimmed device id with DELETE', () async {
    final client = _FakeNetworkClient();

    await DeviceApi(networkClient: client).revokeDevice(' device-1 ');

    expect(client.lastPath, '/v1/devices/device-1');
    expect(client.deleteCalls, 1);
  });

  test('rejects an empty device id without making a request', () async {
    final client = _FakeNetworkClient();

    await expectLater(
      DeviceApi(networkClient: client).revokeDevice('  '),
      throwsArgumentError,
    );
    expect(client.deleteCalls, 0);
  });
}

Map<String, Object?> _envelope(List<Map<String, Object?>> data) => {
      'request_id': 'request-device-1',
      'data': data,
      'meta': {'next_cursor': null},
    };

class _FakeNetworkClient implements NetworkClient {
  _FakeNetworkClient({this.getResponse});

  final Object? getResponse;
  String? lastPath;
  int deleteCalls = 0;

  @override
  Future<Object?> get(String path,
      {Map<String, Object?>? queryParameters}) async {
    lastPath = path;
    return getResponse;
  }

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Object?> delete(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    lastPath = path;
    deleteCalls += 1;
    return null;
  }

  @override
  Future<Object?> put(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) {
    throw UnimplementedError();
  }
}
