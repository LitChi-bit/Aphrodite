import 'package:aphrodite/chat/data/mls_api.dart';
import 'package:aphrodite/chat/e2ee/mls_lifecycle_coordinator.dart';
import 'package:aphrodite/chat/e2ee/openmls_client.dart';
import 'package:aphrodite/core/network/network_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('publishes generated key packages without exposing private state',
      () async {
    final native = _FakeNativeAdapter();
    final network =
        _RecordingNetworkClient(postResponse: _envelope({'ok': true}));
    final coordinator = MlsLifecycleCoordinator(
      api: MlsApi(networkClient: network),
      native: native,
    );

    await coordinator.replenishKeyPackages(
      count: 1,
      expiresAt: DateTime.utc(2026, 8, 12),
    );

    expect(native.generatedCount, 1);
    expect(network.lastPath, '/v1/mls/key-packages');
    expect(network.lastPostData?['key_packages'], isA<List<Object?>>());
  });

  test('claims Welcome material and delegates bootstrap to native', () async {
    final native = _FakeNativeAdapter();
    final coordinator = MlsLifecycleCoordinator(
      api: MlsApi(
        networkClient: _RecordingNetworkClient(
          postResponse: _envelope([
            {
              'conversation_id': 'conversation-1',
              'epoch': 2,
              'welcome': 'AQI',
            },
          ]),
        ),
      ),
      native: native,
    );

    final conversations = await coordinator.claimAndJoinWelcomes();

    expect(conversations, ['conversation-1']);
    expect(native.joinedWelcomes.single.conversationId, 'conversation-1');
    expect(native.joinedWelcomes.single.data, [1, 2]);
  });

  test('rejects state returned for a different conversation before native',
      () async {
    final native = _FakeNativeAdapter();
    final coordinator = MlsLifecycleCoordinator(
      api: MlsApi(
        networkClient: _RecordingNetworkClient(
          getResponse: _envelope({
            'conversation_id': 'conversation-2',
            'epoch': 2,
            'group_info': 'AQ',
            'commit': 'Ag',
          }),
        ),
      ),
      native: native,
    );

    await expectLater(
      coordinator.syncGroupState('conversation-1'),
      throwsA(isA<StateError>()),
    );
    expect(native.appliedStates, isEmpty);
  });

  test('syncs pending proposals through native validation', () async {
    final native = _FakeNativeAdapter();
    final coordinator = MlsLifecycleCoordinator(
      api: MlsApi(
        networkClient: _RecordingNetworkClient(
          getResponse: _envelope([
            {
              'id': 'proposal-1',
              'conversation_id': 'conversation-1',
              'base_epoch': 2,
              'proposal': 'AQI',
              'created_at': '2026-08-03T04:00:00Z',
            },
          ]),
        ),
      ),
      native: native,
    );

    final ids = await coordinator.syncPendingProposals('conversation-1');

    expect(ids, ['proposal-1']);
    expect(native.appliedProposals.single, [1, 2]);
  });

  test('rejects pending proposals for another conversation', () async {
    final native = _FakeNativeAdapter();
    final coordinator = MlsLifecycleCoordinator(
      api: MlsApi(
        networkClient: _RecordingNetworkClient(
          getResponse: _envelope([
            {
              'id': 'proposal-1',
              'conversation_id': 'conversation-2',
              'base_epoch': 2,
              'proposal': 'AQI',
              'created_at': '2026-08-03T04:00:00Z',
            },
          ]),
        ),
      ),
      native: native,
    );

    await expectLater(
      coordinator.syncPendingProposals('conversation-1'),
      throwsA(isA<StateError>()),
    );
    expect(native.appliedProposals, isEmpty);
  });

  test('claims a KeyPackage then publishes native Add proposal at native epoch',
      () async {
    final native = _FakeNativeAdapter();
    final network = _RecordingNetworkClient(
      postResponses: [
        _envelope([
          {
            'id': 'package-1',
            'device_id': 'device-2',
            'ciphersuite': 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
            'key_package': 'AQI',
            'signature': 'Aw',
            'expires_at': '2026-08-12T00:00:00Z',
          },
        ]),
        _envelope({
          'id': 'proposal-1',
          'conversation_id': 'conversation-1',
          'base_epoch': 2,
          'proposal': 'AQI',
          'created_at': '2026-08-03T04:00:00Z',
        }),
      ],
    );
    final coordinator = MlsLifecycleCoordinator(
      api: MlsApi(networkClient: network),
      native: native,
    );

    final published = await coordinator.proposeAddMember(
      conversationId: 'conversation-1',
      targetAccountId: 'account-2',
    );

    expect(network.postPaths, [
      '/v1/accounts/account-2/mls/key-packages:claim?limit=1',
      '/v1/conversations/conversation-1/mls/proposals',
    ]);
    expect(network.postData[1], {
      'base_epoch': 2,
      'proposal': 'AQI',
    });
    expect(published.proposalId, 'proposal-1');
    expect(published.targetAccountId, 'account-2');
    expect(published.targetDeviceId, 'device-2');
    expect(published.keyPackageId, 'package-1');
  });

  test('submits native commit with explicit server metadata', () async {
    final native = _FakeNativeAdapter();
    final network = _RecordingNetworkClient(
      putResponse: _envelope({
        'conversation_id': 'conversation-1',
        'epoch': 3,
        'group_info': null,
        'commit': 'Bw',
      }),
    );
    final coordinator = MlsLifecycleCoordinator(
      api: MlsApi(networkClient: network),
      native: native,
    );

    final state = await coordinator.commitPendingProposals(
      conversationId: 'conversation-1',
      proposalIds: const ['proposal-1'],
      removedDeviceIds: const ['device-2'],
      welcomeTargets: const [],
    );

    expect(state.epoch, 3);
    expect(network.lastPutData?['proposal_ids'], ['proposal-1']);
    expect(network.lastPutData?['removed_device_ids'], ['device-2']);
    expect(network.lastPutData?['commit'], 'Bw');
    expect(network.lastPutData?['group_info'], isNull);
  });

  test('rejects target metadata when native has no Welcome', () async {
    final native = _FakeNativeAdapter();
    final coordinator = MlsLifecycleCoordinator(
      api: MlsApi(networkClient: _RecordingNetworkClient()),
      native: native,
    );

    await expectLater(
      coordinator.commitPendingProposals(
        conversationId: 'conversation-1',
        proposalIds: const [],
        removedDeviceIds: const [],
        welcomeTargets: const [
          OpenMlsWelcomeTarget(
            accountId: 'account-2',
            deviceId: 'device-2',
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('passes matching state directly to native validation', () async {
    final native = _FakeNativeAdapter();
    final coordinator = MlsLifecycleCoordinator(
      api: MlsApi(
        networkClient: _RecordingNetworkClient(
          getResponse: _envelope({
            'conversation_id': 'conversation-1',
            'epoch': 2,
            'group_info': 'AQ',
            'commit': 'Ag',
          }),
        ),
      ),
      native: native,
    );

    await coordinator.syncGroupState('conversation-1');

    expect(native.appliedStates.single.conversationId, 'conversation-1');
    expect(native.appliedStates.single.commit, [2]);
  });
}

Map<String, Object?> _envelope(Object? data) => {
      'request_id': 'request-example',
      'data': data,
      'meta': {'next_cursor': null},
    };

final class _FakeNativeAdapter implements MlsGroupNativeAdapter {
  var generatedCount = 0;
  final joinedWelcomes = <OpenMlsWelcome>[];
  final appliedStates = <OpenMlsGroupState>[];
  final appliedProposals = <List<int>>[];
  var commitBundle = OpenMlsCommitBundle(
    commit: const [7],
    welcome: null,
    groupInfo: null,
    epoch: 3,
  );

  @override
  Future<List<OpenMlsKeyPackage>> generateKeyPackages({
    required int count,
    required DateTime expiresAt,
  }) async {
    generatedCount = count;
    return [
      OpenMlsKeyPackage(
        ciphersuite: 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
        keyPackage: const [1, 2],
        signature: const [3],
        expiresAt: expiresAt,
      ),
    ];
  }

  @override
  Future<void> joinWelcome({required OpenMlsWelcome welcome}) async {
    joinedWelcomes.add(welcome);
  }

  @override
  Future<void> applyGroupState({
    required String conversationId,
    required OpenMlsGroupState state,
  }) async {
    appliedStates.add(state);
  }

  @override
  Future<OpenMlsProposalApplyResult> applyProposal({
    required String conversationId,
    required List<int> proposal,
  }) async {
    appliedProposals.add(List.unmodifiable(proposal));
    return const OpenMlsProposalApplyResult(epoch: 2);
  }

  @override
  Future<OpenMlsAddProposalBundle> proposeAddMember({
    required String conversationId,
    required List<int> keyPackage,
  }) async =>
      OpenMlsAddProposalBundle(proposal: keyPackage, epoch: 2);

  @override
  Future<OpenMlsCommitBundle> commitPendingProposals({
    required String conversationId,
  }) async =>
      commitBundle;
}

final class _RecordingNetworkClient implements NetworkClient {
  _RecordingNetworkClient({
    this.postResponse,
    this.postResponses,
    this.getResponse,
    this.putResponse,
  });

  final Object? postResponse;
  final List<Object?>? postResponses;
  final Object? getResponse;
  final Object? putResponse;
  String? lastPath;
  Map<String, Object?>? lastPostData;
  Map<String, Object?>? lastPutData;
  final postPaths = <String>[];
  final postData = <Map<String, Object?>?>[];
  var _postResponseIndex = 0;

  @override
  Future<Object?> delete(
    String path, {
    Map<String, Object?>? queryParameters,
  }) =>
      throw UnimplementedError();

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    lastPath = path;
    return getResponse;
  }

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    lastPath = path;
    lastPostData = data as Map<String, Object?>?;
    postPaths.add(path);
    postData.add(lastPostData);
    if (postResponses == null) {
      return postResponse;
    }
    if (_postResponseIndex >= postResponses!.length) {
      throw StateError('unexpected POST request');
    }
    return postResponses![_postResponseIndex++];
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
