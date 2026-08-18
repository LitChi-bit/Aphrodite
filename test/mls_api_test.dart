import 'package:aphrodite/chat/data/mls_api.dart';
import 'package:aphrodite/chat/e2ee/openmls_client.dart';
import 'package:aphrodite/core/network/network_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('publishes opaque key packages as raw base64', () async {
    final client = _RecordingNetworkClient(
      postResponse: _envelope({'accepted': 1}),
    );
    final api = MlsApi(networkClient: client);

    await api.publishKeyPackages([
      OpenMlsKeyPackage(
        ciphersuite: 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
        keyPackage: const [1, 2],
        signature: const [3],
        expiresAt: DateTime.utc(2026, 8, 10),
      ),
    ]);

    expect(client.lastPath, '/v1/mls/key-packages');
    expect(client.lastPostData, {
      'key_packages': [
        {
          'ciphersuite': 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
          'key_package': 'AQI',
          'signature': 'Aw',
          'expires_at': '2026-08-10T00:00:00.000Z',
        },
      ],
    });
  });

  test('claims target key packages with server identifiers intact', () async {
    final client = _RecordingNetworkClient(
      postResponse: _envelope([
        {
          'id': 'package-1',
          'device_id': 'target-device-1',
          'ciphersuite': 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
          'key_package': 'AQI',
          'signature': 'AwQ',
          'expires_at': '2026-08-12T04:00:00Z',
        },
      ]),
    );
    final api = MlsApi(networkClient: client);

    final packages = await api.claimKeyPackages('target-account-1', limit: 2);

    expect(
      client.lastPath,
      '/v1/accounts/target-account-1/mls/key-packages:claim?limit=2',
    );
    expect(packages.single.id, 'package-1');
    expect(packages.single.deviceId, 'target-device-1');
    expect(packages.single.keyPackage, [1, 2]);
    expect(packages.single.signature, [3, 4]);
    expect(packages.single.expiresAt, DateTime.utc(2026, 8, 12, 4));
  });

  test('rejects invalid target key package claim input', () async {
    final api = MlsApi(networkClient: _RecordingNetworkClient());

    await expectLater(
      api.claimKeyPackages(' target-account-1 '),
      throwsArgumentError,
    );
    await expectLater(
      api.claimKeyPackages('target-account-1', limit: 21),
      throwsArgumentError,
    );
  });

  test('claims welcomes and decodes raw base64 protocol material', () async {
    final api = MlsApi(
      networkClient: _RecordingNetworkClient(
        postResponse: _envelope([
          {
            'id': 'welcome-1',
            'conversation_id': 'conversation-1',
            'epoch': 3,
            'welcome': 'AQI',
            'created_at': '2026-08-03T04:00:00Z',
          },
        ]),
      ),
    );

    final welcomes = await api.claimWelcomes();

    expect(welcomes.single.conversationId, 'conversation-1');
    expect(welcomes.single.epoch, 3);
    expect(welcomes.single.data, [1, 2]);
  });

  test('commits through PUT with explicit welcome routing metadata', () async {
    final client = _RecordingNetworkClient(
      putResponse: _envelope({
        'conversation_id': 'conversation-1',
        'epoch': 4,
        'group_info': 'AQ',
        'commit': 'Ag',
        'committed_at': '2026-08-03T04:00:00Z',
      }),
    );
    final api = MlsApi(networkClient: client);

    final state = await api.commit(
      OpenMlsCommit(
        conversationId: 'conversation-1',
        epoch: 4,
        groupInfo: const [1],
        commit: const [2],
        welcomes: [
          OpenMlsWelcome(
            conversationId: 'conversation-1',
            epoch: 4,
            data: const [3],
            target: const OpenMlsWelcomeTarget(
              accountId: 'account-2',
              deviceId: 'device-2',
            ),
          ),
        ],
        proposalIds: const ['proposal-1'],
        removedDeviceIds: const ['device-3'],
      ),
    );

    expect(client.lastPath, '/v1/conversations/conversation-1/mls/state');
    expect(client.lastPutData?['welcomes'], [
      {
        'target_account_id': 'account-2',
        'target_device_id': 'device-2',
        'welcome': 'Aw',
      },
    ]);
    expect(state.epoch, 4);
    expect(state.groupInfo, [1]);
  });

  test('preserves an absent group info value as JSON null', () async {
    final client = _RecordingNetworkClient(
      putResponse: _envelope({
        'conversation_id': 'conversation-1',
        'epoch': 4,
        'group_info': null,
        'commit': 'Ag',
        'committed_at': '2026-08-03T04:00:00Z',
      }),
    );
    final api = MlsApi(networkClient: client);

    final state = await api.commit(
      OpenMlsCommit(
        conversationId: 'conversation-1',
        epoch: 4,
        groupInfo: null,
        commit: const [2],
        welcomes: const [],
        proposalIds: const [],
        removedDeviceIds: const [],
      ),
    );

    expect(client.lastPutData?['group_info'], isNull);
    expect(state.groupInfo, isNull);
  });

  test('rejects empty group info when serializing a commit', () async {
    final api = MlsApi(networkClient: _RecordingNetworkClient());

    await expectLater(
      api.commit(
        OpenMlsCommit(
          conversationId: 'conversation-1',
          epoch: 1,
          groupInfo: const [],
          commit: const [2],
          welcomes: const [],
          proposalIds: const [],
          removedDeviceIds: const [],
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rejects unpadded-base64 violations and missing welcome targets',
      () async {
    final api = MlsApi(
      networkClient: _RecordingNetworkClient(
        postResponse: _envelope([
          {
            'id': 'welcome-1',
            'conversation_id': 'conversation-1',
            'epoch': 3,
            'welcome': 'AQ==',
            'created_at': '2026-08-03T04:00:00Z',
          },
        ]),
      ),
    );

    await expectLater(api.claimWelcomes(), throwsA(isA<FormatException>()));
    await expectLater(
      api.commit(
        OpenMlsCommit(
          conversationId: 'conversation-1',
          epoch: 1,
          groupInfo: const [1],
          commit: const [2],
          welcomes: [
            OpenMlsWelcome(
              conversationId: 'conversation-1',
              epoch: 1,
              data: const [3],
            ),
          ],
          proposalIds: const [],
          removedDeviceIds: const [],
        ),
      ),
      throwsArgumentError,
    );
  });
}

Map<String, Object?> _envelope(Object? data) => {
      'request_id': 'request-example',
      'data': data,
      'meta': {'next_cursor': null},
    };

class _RecordingNetworkClient implements NetworkClient {
  _RecordingNetworkClient({this.postResponse, this.putResponse});

  final Object? postResponse;
  final Object? putResponse;
  String? lastPath;
  Map<String, Object?>? lastPostData;
  Map<String, Object?>? lastPutData;

  @override
  Future<Object?> delete(
    String path, {
    Map<String, Object?>? queryParameters,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? queryParameters,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    lastPath = path;
    lastPostData = data as Map<String, Object?>?;
    return postResponse;
  }

  @override
  Future<Object?> put(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    lastPath = path;
    lastPutData = data as Map<String, Object?>?;
    return putResponse;
  }
}
