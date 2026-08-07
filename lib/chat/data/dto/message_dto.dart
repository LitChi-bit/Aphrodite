import 'dart:convert';

import '../../e2ee/e2ee_client.dart';
import '../../models/message.dart';

class MessageDto {
  const MessageDto({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.clientMessageId,
    required this.kind,
    required this.ciphertext,
    required this.encryption,
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
  final EncryptedPayload encryption;
  final String? decryptedText;
  final String? replyToMessageId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  factory MessageDto.fromJson(Map<String, Object?> json) => MessageDto(
        id: _requiredString(json['id'], 'id'),
        conversationId:
            _requiredString(json['conversation_id'], 'conversation_id'),
        senderId: _requiredString(json['sender_id'], 'sender_id'),
        clientMessageId:
            _requiredString(json['client_message_id'], 'client_message_id'),
        kind: _requiredKind(json['kind']),
        ciphertext: _requiredString(json['ciphertext'], 'ciphertext'),
        encryption: _requiredEncryption(
          json['encryption'],
          _requiredString(json['ciphertext'], 'ciphertext'),
        ),
        decryptedText:
            _optionalString(json['decrypted_text'], 'decrypted_text'),
        replyToMessageId: _optionalString(json['reply_to'], 'reply_to'),
        createdAt: _requiredDate(json['created_at'], 'created_at'),
        editedAt: _dateOrNull(json['edited_at'], 'edited_at'),
        deletedAt: _dateOrNull(json['deleted_at'], 'deleted_at'),
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

  static String _requiredString(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field must be a non-empty string');
    }
    return value;
  }

  static String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) throw FormatException('$field must be a string');
    return value;
  }

  EncryptedPayload toEncryptedPayload() => encryption;

  static EncryptedPayload _requiredEncryption(
    Object? value,
    String ciphertext,
  ) {
    if (value is! Map) {
      throw const FormatException('encryption must be an object');
    }
    final scheme = _requiredString(value['scheme'], 'encryption.scheme');
    final groupId = _requiredString(value['group_id'], 'encryption.group_id');
    final epoch = value['epoch'];
    if (epoch is! int || epoch < 0) {
      throw const FormatException(
          'encryption.epoch must be a non-negative integer');
    }
    return EncryptedPayload(
      ciphertext: _decodeBase64UrlNoPadding(ciphertext, 'ciphertext'),
      scheme: scheme,
      groupId: groupId,
      epoch: epoch,
      header: _decodeBase64UrlNoPadding(
        _requiredString(value['header'], 'encryption.header'),
        'encryption.header',
      ),
    );
  }

  static List<int> _decodeBase64UrlNoPadding(String value, String field) {
    if (value.contains('=') || !RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(value)) {
      throw FormatException('$field must be unpadded base64url');
    }
    final remainder = value.length % 4;
    if (remainder == 1) {
      throw FormatException('$field must be valid base64url');
    }
    final normalized =
        remainder == 0 ? value : '$value${'=' * (4 - remainder)}';
    try {
      return base64Url.decode(normalized);
    } on FormatException {
      throw FormatException('$field must be valid base64url');
    }
  }

  static String _requiredKind(Object? value) {
    final kind = _requiredString(value, 'kind');
    if (!ChatMessageKind.values.any((candidate) => candidate.name == kind)) {
      throw const FormatException('kind is invalid');
    }
    return kind;
  }

  static DateTime? _dateOrNull(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) throw FormatException('$field must be a string');
    return _date(value, field);
  }

  static DateTime _requiredDate(Object? value, String field) {
    if (value is! String) throw FormatException('$field is required');
    return _date(value, field);
  }

  static DateTime _date(String value, String field) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('$field must be ISO-8601');
    return parsed;
  }
}
