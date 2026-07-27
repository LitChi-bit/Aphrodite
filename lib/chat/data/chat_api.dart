import '../../core/network/network_client.dart';

class ChatApi {
  const ChatApi({required NetworkClient networkClient})
      : _networkClient = networkClient;

  final NetworkClient _networkClient;

  Future<Object?> getConversations({String? cursor, int limit = 50}) {
    return _networkClient.get(
      '/v1/conversations',
      queryParameters: {'cursor': cursor, 'limit': limit},
    );
  }

  Future<Object?> getMessages({
    required String conversationId,
    String? cursor,
    int limit = 50,
  }) {
    return _networkClient.get(
      '/v1/conversations/$conversationId/messages',
      queryParameters: {
        'cursor': cursor,
        'limit': limit,
        'direction': 'backward',
      },
    );
  }

  Future<Object?> sendMessage({
    required String conversationId,
    required Map<String, Object?> encryptedEnvelope,
  }) {
    return _networkClient.post(
      '/v1/conversations/$conversationId/messages',
      data: encryptedEnvelope,
    );
  }
}
