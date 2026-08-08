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
}

final class _RecordingNetworkClient implements NetworkClient {
  _RecordingNetworkClient({this.postResponse, this.getResponse});

  final Object? postResponse;
  final Object? getResponse;
  String? lastPath;
  Map<String, Object?>? lastPostData;

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
    return postResponse;
  }

  @override
  Future<Object?> put(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) =>
      throw UnimplementedError();
}
