import '../data/mls_api.dart';
import 'openmls_client.dart';

/// Native operations needed to synchronize public MLS delivery material.
///
/// The adapter owns all private MLS state. This coordinator only transports
/// opaque protocol bytes and validates their conversation binding.
abstract interface class MlsGroupNativeAdapter {
  Future<List<OpenMlsKeyPackage>> generateKeyPackages({
    required int count,
    required DateTime expiresAt,
  });

  Future<void> joinWelcome({
    required OpenMlsWelcome welcome,
  });

  Future<void> applyGroupState({
    required String conversationId,
    required OpenMlsGroupState state,
  });

  Future<OpenMlsProposalApplyResult> applyProposal({
    required String conversationId,
    required List<int> proposal,
  });

  Future<OpenMlsAddProposalBundle> proposeAddMember({
    required String conversationId,
    required List<int> keyPackage,
  });

  Future<OpenMlsCommitBundle> commitPendingProposals({
    required String conversationId,
  });
}

class OpenMlsProposalApplyResult {
  const OpenMlsProposalApplyResult({required this.epoch});

  final int epoch;
}

class OpenMlsAddProposalBundle {
  OpenMlsAddProposalBundle({
    required List<int> proposal,
    required this.epoch,
  }) : proposal = List.unmodifiable(proposal);

  final List<int> proposal;
  final int epoch;
}

class OpenMlsCommitBundle {
  OpenMlsCommitBundle({
    required List<int> commit,
    required List<int>? welcome,
    required List<int>? groupInfo,
    required this.epoch,
  })  : commit = List.unmodifiable(commit),
        welcome = welcome == null ? null : List.unmodifiable(welcome),
        groupInfo = groupInfo == null ? null : List.unmodifiable(groupInfo);

  final List<int> commit;
  final List<int>? welcome;
  final List<int>? groupInfo;
  final int epoch;
}

/// Coordinates the server-facing MLS lifecycle without exposing private state.
final class MlsLifecycleCoordinator {
  const MlsLifecycleCoordinator({
    required MlsApi api,
    required MlsGroupNativeAdapter native,
  })  : _api = api,
        _native = native;

  final MlsApi _api;
  final MlsGroupNativeAdapter _native;

  Future<void> replenishKeyPackages({
    required int count,
    required DateTime expiresAt,
  }) async {
    final packages = await _native.generateKeyPackages(
      count: count,
      expiresAt: expiresAt,
    );
    if (packages.isEmpty) {
      throw StateError(
          'native MLS key package generation returned no packages');
    }
    await _api.publishKeyPackages(packages);
  }

  /// Claims each pending Welcome and lets the native adapter validate its group.
  ///
  /// A Welcome is the only supported bootstrap path for a device without local
  /// private group state. Existing members must use [syncGroupState].
  Future<List<String>> claimAndJoinWelcomes() async {
    final welcomes = await _api.claimWelcomes();
    final conversations = <String>[];
    for (final welcome in welcomes) {
      _requireCanonicalConversationId(welcome.conversationId);
      await _native.joinWelcome(welcome: welcome);
      conversations.add(welcome.conversationId);
    }
    return List.unmodifiable(conversations);
  }

  /// Fetches pending proposals and lets the native adapter validate and store
  /// each one. Proposal bytes remain opaque to Dart and the coordination API.
  Future<List<String>> syncPendingProposals(String conversationId) async {
    _requireCanonicalConversationId(conversationId);
    final proposals = await _api.listProposals(conversationId);
    final acceptedProposalIDs = <String>[];
    for (final proposal in proposals) {
      if (proposal.conversationId != conversationId) {
        throw StateError('MLS proposal conversation ID does not match request');
      }
      final result = await _native.applyProposal(
        conversationId: conversationId,
        proposal: proposal.data,
      );
      if (result.epoch != proposal.baseEpoch) {
        throw StateError(
            'native MLS proposal epoch does not match server state');
      }
      if (proposal.id == null) {
        throw StateError('server MLS proposal has no ID');
      }
      acceptedProposalIDs.add(proposal.id!);
    }
    return List.unmodifiable(acceptedProposalIDs);
  }

  /// Claims one public KeyPackage for [targetAccountId], lets native OpenMLS
  /// create the Add proposal, then publishes it with the native base epoch.
  ///
  /// The returned metadata preserves the target device and server KeyPackage ID
  /// for the later Commit/Welcome business workflow; neither is inferred from
  /// opaque MLS bytes.
  Future<OpenMlsPublishedAddProposal> proposeAddMember({
    required String conversationId,
    required String targetAccountId,
  }) async {
    _requireCanonicalConversationId(conversationId);
    _requireCanonicalIdentifier(targetAccountId, 'targetAccountId');
    final claimed = await _api.claimKeyPackages(targetAccountId);
    if (claimed.length != 1) {
      throw StateError('server must claim exactly one MLS KeyPackage');
    }
    final keyPackage = claimed.single;
    if (keyPackage.ciphersuite !=
        'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519') {
      throw StateError('claimed MLS KeyPackage has an unsupported ciphersuite');
    }
    final nativeProposal = await _native.proposeAddMember(
      conversationId: conversationId,
      keyPackage: keyPackage.keyPackage,
    );
    if (nativeProposal.epoch < 0 || nativeProposal.proposal.isEmpty) {
      throw StateError('native MLS Add proposal is invalid');
    }
    final published = await _api.publishProposal(
      OpenMlsProposal(
        conversationId: conversationId,
        baseEpoch: nativeProposal.epoch,
        data: nativeProposal.proposal,
      ),
    );
    if (published.id == null ||
        published.conversationId != conversationId ||
        published.baseEpoch != nativeProposal.epoch) {
      throw StateError(
          'server MLS Add proposal response does not match native proposal');
    }
    return OpenMlsPublishedAddProposal(
      proposalId: published.id!,
      conversationId: conversationId,
      baseEpoch: nativeProposal.epoch,
      targetAccountId: targetAccountId,
      targetDeviceId: keyPackage.deviceId,
      keyPackageId: keyPackage.id,
    );
  }

  /// Creates the next Commit from native pending proposals and submits only
  /// explicitly supplied server metadata alongside the opaque native bytes.
  Future<OpenMlsGroupState> commitPendingProposals({
    required String conversationId,
    required List<String> proposalIds,
    required List<String> removedDeviceIds,
    required List<OpenMlsWelcomeTarget> welcomeTargets,
  }) async {
    _requireCanonicalConversationId(conversationId);
    final bundle = await _native.commitPendingProposals(
      conversationId: conversationId,
    );
    if (bundle.epoch < 0) {
      throw StateError('native MLS commit epoch is invalid');
    }
    if ((bundle.welcome == null) != welcomeTargets.isEmpty) {
      throw StateError('native MLS Welcome does not match explicit targets');
    }
    final welcomes = bundle.welcome == null
        ? const <OpenMlsWelcome>[]
        : [
            for (final target in welcomeTargets)
              OpenMlsWelcome(
                conversationId: conversationId,
                epoch: bundle.epoch,
                data: bundle.welcome!,
                target: target,
              ),
          ];
    final response = await _api.commit(
      OpenMlsCommit(
        conversationId: conversationId,
        epoch: bundle.epoch,
        groupInfo: bundle.groupInfo,
        commit: bundle.commit,
        welcomes: welcomes,
        proposalIds: proposalIds,
        removedDeviceIds: removedDeviceIds,
      ),
    );
    if (response.conversationId != conversationId ||
        response.epoch != bundle.epoch) {
      throw StateError(
          'server MLS commit response does not match native commit');
    }
    return response;
  }

  /// Applies exactly one authenticated next Commit to an existing local group.
  ///
  /// The native adapter enforces the group ID and epoch transition. A device
  /// that has no group must first join through a Welcome instead.
  Future<void> syncGroupState(String conversationId) async {
    _requireCanonicalConversationId(conversationId);
    final state = await _api.getGroupState(conversationId);
    if (state.conversationId != conversationId) {
      throw StateError('MLS state conversation ID does not match request');
    }
    await _native.applyGroupState(
      conversationId: conversationId,
      state: state,
    );
  }

  static void _requireCanonicalConversationId(String conversationId) {
    _requireCanonicalIdentifier(conversationId, 'conversationId');
  }

  static void _requireCanonicalIdentifier(String value, String name) {
    if (value.isEmpty || value.trim() != value) {
      throw ArgumentError.value(
        value,
        name,
        'must be non-empty and have no surrounding whitespace',
      );
    }
  }
}

class OpenMlsPublishedAddProposal {
  const OpenMlsPublishedAddProposal({
    required this.proposalId,
    required this.conversationId,
    required this.baseEpoch,
    required this.targetAccountId,
    required this.targetDeviceId,
    required this.keyPackageId,
  });

  final String proposalId;
  final String conversationId;
  final int baseEpoch;
  final String targetAccountId;
  final String targetDeviceId;
  final String keyPackageId;
}
