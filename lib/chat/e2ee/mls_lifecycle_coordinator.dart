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
    if (conversationId.isEmpty || conversationId.trim() != conversationId) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'must be non-empty and have no surrounding whitespace',
      );
    }
  }
}
