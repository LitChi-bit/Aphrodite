import 'dart:convert';

import '../data/chat_api.dart';
import '../e2ee/e2ee_client.dart';
import '../models/message.dart';

class MessageSender {
  const MessageSender({
    required ChatApi api,
    required E2eeClient encryption,
  })  : _api = api,
        _encryption = encryption;

  final ChatApi _api;
  final E2eeClient _encryption;

  Future<ChatMessage> sendText({
    required String conversationId,
    required String senderId,
    required String clientMessageId,
    required String text,
    String? replyToMessageId,
    DateTime? createdAt,
  }) async {
    final normalizedConversationId = _requiredValue(
      conversationId,
      'conversationId',
    );
    final normalizedSenderId = _requiredValue(senderId, 'senderId');
    final normalizedClientMessageId = _requiredValue(
      clientMessageId,
      'clientMessageId',
    );
    final normalizedText = _requiredValue(text, 'text');
    final localCreatedAt = (createdAt ?? DateTime.now()).toUtc();
    final plaintext = utf8.encode(
      jsonEncode({
        'version': 1,
        'kind': 'text',
        'content': normalizedText,
        'client_message_id': normalizedClientMessageId,
        'reply_to': replyToMessageId,
        'created_at': localCreatedAt.toIso8601String(),
      }),
    );
    final encrypted = await _encryption.encryptMessage(
      conversationId: normalizedConversationId,
      plaintext: plaintext,
    );
    final confirmed = await _api.sendMessage(
      conversationId: normalizedConversationId,
      encryptedEnvelope: {
        'client_message_id': normalizedClientMessageId,
        'kind': 'text',
        'ciphertext': base64Encode(encrypted.ciphertext).replaceAll('=', ''),
        'encryption': {
          'scheme': encrypted.scheme,
          'group_id': encrypted.groupId,
          'epoch': encrypted.epoch,
          'header': base64Encode(encrypted.header).replaceAll('=', ''),
        },
        'reply_to': replyToMessageId,
      },
    );
    if (confirmed.conversationId != normalizedConversationId ||
        confirmed.senderId != normalizedSenderId ||
        confirmed.clientMessageId != normalizedClientMessageId ||
        confirmed.kind != ChatMessageKind.text.name ||
        confirmed.replyToMessageId != replyToMessageId) {
      throw const ChatSendProtocolException();
    }
    return ChatMessage(
      id: confirmed.id,
      conversationId: confirmed.conversationId,
      senderId: confirmed.senderId,
      clientMessageId: confirmed.clientMessageId,
      kind: ChatMessageKind.text,
      status: ChatMessageStatus.sent,
      encryptionState: MessageEncryptionState.plain,
      text: normalizedText,
      replyToMessageId: confirmed.replyToMessageId,
      createdAt: confirmed.createdAt,
      editedAt: confirmed.editedAt,
      deletedAt: confirmed.deletedAt,
    );
  }

  static String _requiredValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty');
    }
    return normalized;
  }
}

class ChatSendProtocolException implements Exception {
  const ChatSendProtocolException();

  @override
  String toString() => 'Chat server response does not match the sent message.';
}
