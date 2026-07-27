abstract interface class MlsGroupManager {
  Future<void> bootstrap({
    required String conversationId,
    required String groupId,
  });

  Future<bool> isReady(String conversationId);

  Future<void> processEnvelope({
    required String groupId,
    required List<int> envelope,
  });

  Future<void> removeGroup(String conversationId);
}
