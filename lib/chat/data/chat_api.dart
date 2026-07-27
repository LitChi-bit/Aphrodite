import '../../core/network/network_client.dart';
import 'dto/api_envelope.dart';
import 'dto/conversation_dto.dart';
import 'dto/message_dto.dart';

class ChatApi {
  const ChatApi({required NetworkClient networkClient})
      : _networkClient = networkClient;

  final NetworkClient _networkClient;

  Future<CursorPage<ConversationDto>> getConversations({
    String? cursor,
    int limit = 50,
  }) async {
    final response = await _networkClient.get(
      '/v1/conversations',
      queryParameters: {'cursor': cursor, 'limit': limit},
    );
    final envelope = ApiEnvelope<List<ConversationDto>>.fromJson(
      requireJsonMap(response, 'conversation response'),
      (data) => requireJsonList(data, 'conversation data')
          .map(
            (item) => ConversationDto.fromJson(
              requireJsonMap(item, 'conversation'),
            ),
          )
          .toList(growable: false),
    );
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  Future<CursorPage<MessageDto>> getMessages({
    required String conversationId,
    String? cursor,
    int limit = 50,
  }) async {
    final response = await _networkClient.get(
      '/v1/conversations/$conversationId/messages',
      queryParameters: {
        'cursor': cursor,
        'limit': limit,
        'direction': 'backward',
      },
    );
    final envelope = ApiEnvelope<List<MessageDto>>.fromJson(
      requireJsonMap(response, 'message response'),
      (data) => requireJsonList(data, 'message data')
          .map(
            (item) => MessageDto.fromJson(requireJsonMap(item, 'message')),
          )
          .toList(growable: false),
    );
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  Future<MessageDto> sendMessage({
    required String conversationId,
    required Map<String, Object?> encryptedEnvelope,
  }) async {
    final response = await _networkClient.post(
      '/v1/conversations/$conversationId/messages',
      data: encryptedEnvelope,
    );
    final envelope = ApiEnvelope<MessageDto>.fromJson(
      requireJsonMap(response, 'send message response'),
      (data) => MessageDto.fromJson(requireJsonMap(data, 'message')),
    );
    return envelope.data;
  }
}
