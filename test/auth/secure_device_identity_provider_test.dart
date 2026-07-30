import 'dart:convert';

import 'package:aphrodite/auth/data/secure_device_identity_provider.dart';
import 'package:aphrodite/core/storage/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates and persists a stable Ed25519 device identity', () async {
    final store = _MemorySecureStore();
    final provider = SecureDeviceIdentityProvider(
      secureStore: store,
      deviceName: ' Aphrodite Android ',
      platform: 'ANDROID',
    );

    final first = await provider.getOrCreate();
    final second = await SecureDeviceIdentityProvider(
      secureStore: store,
      deviceName: 'Aphrodite Android',
      platform: 'android',
    ).getOrCreate();

    expect(second.deviceId, first.deviceId);
    expect(second.identityPublicKeyBase64, first.identityPublicKeyBase64);
    expect(first.deviceName, 'Aphrodite Android');
    expect(first.platform, 'android');
    expect(base64Decode(first.identityPublicKeyBase64), hasLength(32));
    expect(store.values.keys, {
      'auth.identity_private_key_seed',
      'auth.device_id',
    });
    expect(base64Decode(store.values['auth.identity_private_key_seed']!),
        hasLength(32));
  });

  test('coalesces concurrent identity creation', () async {
    final store = _MemorySecureStore();
    final provider = SecureDeviceIdentityProvider(
      secureStore: store,
      deviceName: 'Aphrodite Test',
      platform: 'ios',
    );

    final identities = await Future.wait([
      provider.getOrCreate(),
      provider.getOrCreate(),
      provider.getOrCreate(),
    ]);

    expect(
        identities.map((identity) => identity.deviceId).toSet(), hasLength(1));
    expect(store.writeCounts['auth.identity_private_key_seed'], 1);
    expect(store.writeCounts['auth.device_id'], 1);
  });

  test('rejects partial or corrupted stored identity without rotating it',
      () async {
    final cases = <Map<String, String>>[
      {'auth.device_id': '00000000-0000-4000-8000-000000000001'},
      {'auth.identity_private_key_seed': base64Encode(List<int>.filled(32, 1))},
      {
        'auth.device_id': 'not-a-uuid',
        'auth.identity_private_key_seed': base64Encode(List<int>.filled(32, 1)),
      },
      {
        'auth.device_id': '00000000-0000-4000-8000-000000000001',
        'auth.identity_private_key_seed': 'not-base64',
      },
      {
        'auth.device_id': '00000000-0000-4000-8000-000000000001',
        'auth.identity_private_key_seed': base64Encode(List<int>.filled(31, 1)),
      },
    ];

    for (final values in cases) {
      final store = _MemorySecureStore()..values.addAll(values);
      final provider = SecureDeviceIdentityProvider(
        secureStore: store,
        deviceName: 'Aphrodite Test',
        platform: 'linux',
      );

      await expectLater(
          provider.getOrCreate(), throwsA(isA<DeviceIdentityException>()));
      expect(store.values, values);
    }
  });

  test('rolls back private seed if device id persistence fails', () async {
    final store = _MemorySecureStore(failWriteKey: 'auth.device_id');
    final provider = SecureDeviceIdentityProvider(
      secureStore: store,
      deviceName: 'Aphrodite Test',
      platform: 'windows',
    );

    await expectLater(provider.getOrCreate(), throwsStateError);

    expect(store.values, isEmpty);
  });

  test('reports both failures if rollback cannot remove private seed',
      () async {
    final store = _MemorySecureStore(
      failWriteKey: 'auth.device_id',
      failDeleteKey: 'auth.identity_private_key_seed',
    );
    final provider = SecureDeviceIdentityProvider(
      secureStore: store,
      deviceName: 'Aphrodite Test',
      platform: 'windows',
    );

    final expectation = throwsA(
      isA<DeviceIdentityPersistenceException>()
          .having((error) => error.writeError, 'writeError', isA<StateError>())
          .having((error) => error.rollbackError, 'rollbackError',
              isA<StateError>()),
    );
    await expectLater(provider.getOrCreate(), expectation);

    expect(store.values, contains('auth.identity_private_key_seed'));
  });

  test('rejects unsupported metadata', () {
    expect(
      () => SecureDeviceIdentityProvider(
        secureStore: _MemorySecureStore(),
        deviceName: ' ',
        platform: 'android',
      ),
      throwsArgumentError,
    );
    expect(
      () => SecureDeviceIdentityProvider(
        secureStore: _MemorySecureStore(),
        deviceName: 'Aphrodite Test',
        platform: 'unknown',
      ),
      throwsArgumentError,
    );
  });
}

class _MemorySecureStore implements SecureStore {
  _MemorySecureStore({this.failWriteKey, this.failDeleteKey});

  final String? failWriteKey;
  final String? failDeleteKey;
  final Map<String, String> values = {};
  final Map<String, int> writeCounts = {};

  @override
  Future<void> delete(String key) async {
    if (key == failDeleteKey) {
      throw StateError('controlled delete failure');
    }
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writeCounts[key] = (writeCounts[key] ?? 0) + 1;
    if (key == failWriteKey) throw StateError('controlled storage failure');
    values[key] = value;
  }
}
