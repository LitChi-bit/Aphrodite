import 'e2ee_client.dart';

/// Contract implemented by a Rust/OpenMLS FFI adapter.
///
/// All private MLS state remains owned by the native adapter and its persistent
/// OpenMls StorageProvider. Dart receives only opaque protocol material.
abstract interface class OpenMlsClient implements E2eeClient {
  Future<OpenMlsDeviceIdentity> initializeDevice({
    required String deviceId,
  });

  Future<List<OpenMlsKeyPackage>> generateKeyPackages({
    required int count,
    required DateTime expiresAt,
  });

  Future<void> joinGroup({
    required String conversationId,
    required OpenMlsWelcome welcome,
  });

  Future<void> applyGroupState({
    required String conversationId,
    required OpenMlsGroupState state,
  });

  Future<OpenMlsProposal> createProposal({
    required String conversationId,
    required OpenMlsProposalKind kind,
    required List<int> proposalData,
  });

  Future<OpenMlsCommit> createCommit({
    required String conversationId,
    required List<OpenMlsProposal> proposals,
  });

  Future<void> removeLocalGroup(String conversationId);

  Future<void> destroyDeviceState();
}

class OpenMlsDeviceIdentity {
  OpenMlsDeviceIdentity({
    required this.deviceId,
    required List<int> publicIdentity,
  }) : publicIdentity = List.unmodifiable(publicIdentity);

  final String deviceId;
  final List<int> publicIdentity;
}

class OpenMlsKeyPackage {
  OpenMlsKeyPackage({
    required this.ciphersuite,
    required List<int> keyPackage,
    required List<int> signature,
    required this.expiresAt,
  })  : keyPackage = List.unmodifiable(keyPackage),
        signature = List.unmodifiable(signature);

  final String ciphersuite;
  final List<int> keyPackage;
  final List<int> signature;
  final DateTime expiresAt;
}

class OpenMlsWelcome {
  OpenMlsWelcome({
    required this.conversationId,
    required this.epoch,
    required List<int> data,
    this.target,
  }) : data = List.unmodifiable(data);

  final String conversationId;
  final int epoch;
  final List<int> data;
  final OpenMlsWelcomeTarget? target;
}

class OpenMlsWelcomeTarget {
  const OpenMlsWelcomeTarget({
    required this.accountId,
    required this.deviceId,
  });

  final String accountId;
  final String deviceId;
}

class OpenMlsGroupState {
  OpenMlsGroupState({
    required this.conversationId,
    required this.epoch,
    required List<int> groupInfo,
    required List<int> commit,
  })  : groupInfo = List.unmodifiable(groupInfo),
        commit = List.unmodifiable(commit);

  final String conversationId;
  final int epoch;
  final List<int> groupInfo;
  final List<int> commit;
}

enum OpenMlsProposalKind { add, remove, update, custom }

class OpenMlsProposal {
  OpenMlsProposal({
    this.id,
    required this.conversationId,
    required this.baseEpoch,
    required List<int> data,
  }) : data = List.unmodifiable(data);

  final String? id;
  final String conversationId;
  final int baseEpoch;
  final List<int> data;
}

class OpenMlsCommit {
  OpenMlsCommit({
    required this.conversationId,
    required this.epoch,
    required List<int> groupInfo,
    required List<int> commit,
    required List<OpenMlsWelcome> welcomes,
    required List<String> proposalIds,
    required List<String> removedDeviceIds,
  })  : groupInfo = List.unmodifiable(groupInfo),
        commit = List.unmodifiable(commit),
        welcomes = List.unmodifiable(welcomes),
        proposalIds = List.unmodifiable(proposalIds),
        removedDeviceIds = List.unmodifiable(removedDeviceIds);

  final String conversationId;
  final int epoch;
  final List<int> groupInfo;
  final List<int> commit;
  final List<OpenMlsWelcome> welcomes;
  final List<String> proposalIds;
  final List<String> removedDeviceIds;
}
