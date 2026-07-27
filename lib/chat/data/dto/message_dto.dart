import '../../models/message.dart';

class MessageDto {
  const MessageDto({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.clientMessageId,
    required this.kind,
    required this.ciphertext,
    required this.createdAt,
    this.replyToMessageId,
    this.editedAt,
    this.deletedAt,
    this.decryptedText,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String clientMessageId;
  final String kind;
  final String ciphertext;
  final String? decryptedText;
  final String? replyToMessageId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  factory MessageDto.fromJson(Map<String, Object?> json) => MessageDto(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        clientMessageId: json['client_message_id'] as String,
        kind: json['kind'] as String,
        ciphertext: json['ciphertext'] as String,
        decryptedText: json['decrypted_text'] as String?,
        replyToMessageId: json['reply_to'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        editedAt: _dateOrNull(json['edited_at']),
        deletedAt: _dateOrNull(json['deleted_at']),
      );

  ChatMessage toDomain() => ChatMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        clientMessageId: clientMessageId,
        kind: ChatMessageKind.values.byName(kind),
        status: deletedAt == null
            ? ChatMessageStatus.sent
            : ChatMessageStatus.deleted,
        encryptionState: decryptedText == null
            ? MessageEncryptionState.encrypted
            : MessageEncryptionState.plain,
        text: decryptedText,
        replyToMessageId: replyToMessageId,
        createdAt: createdAt,
        editedAt: editedAt,
        deletedAt: deletedAt,
      );

  static DateTime? _dateOrNull(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
