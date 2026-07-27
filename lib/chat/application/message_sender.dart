import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../data/chat_api.dart';
import '../data/chat_database.dart';
import '../e2ee/e2ee_client.dart';
import '../models/message.dart';

class MessageSender {
  const MessageSender({
    required ChatApi api,
    required ChatDatabase database,
    required E2eeClient encryption,
  })  : _api = api,
        _database = database,
        _encryption = encryption;

  final ChatApi _api;
  final ChatDatabase _database;
  final E2eeClient _encryption;

  static const Uuid _uuid = Uuid();

  Future<void> sendText({
    required String conversationId,
    required String senderId,
    required String text,
    String? replyToMessageId,
  }) async {
    final clientMessageId = _uuid.v4();
    final createdAt = DateTime.now().toUtc();
    final pending = ChatMessage(
      id: 'pending-$clientMessageId',
      conversationId: conversationId,
      senderId: senderId,
      clientMessageId: clientMessageId,
      kind: ChatMessageKind.text,
      status: ChatMessageStatus.sending,
      encryptionState: MessageEncryptionState.plain,
      text: text,
      replyToMessageId: replyToMessageId,
      createdAt: createdAt,
    );
    await _database.savePendingMessage(pending);

    final plaintext = utf8.encode(
      '{"version":1,"kind":"text","content":${jsonEncode(text)},'
      '"client_message_id":"$clientMessageId",'
      '"reply_to":${jsonEncode(replyToMessageId)},'
      '"created_at":"${createdAt.toIso8601String()}"}',
    );
    final encrypted = await _encryption.encryptMessage(
      conversationId: conversationId,
      plaintext: plaintext,
    );
    await _api.sendMessage(
      conversationId: conversationId,
      encryptedEnvelope: {
        'client_message_id': clientMessageId,
        'kind': 'text',
        'ciphertext': base64Encode(encrypted.ciphertext),
        'encryption': {
          'scheme': encrypted.scheme,
          'group_id': encrypted.groupId,
          'epoch': encrypted.epoch,
          'header': base64Encode(encrypted.header),
        },
        'reply_to': replyToMessageId,
      },
    );
  }
}
