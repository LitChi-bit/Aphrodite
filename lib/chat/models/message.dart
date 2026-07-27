import 'attachment.dart';

enum ChatMessageKind { text, image, video, audio, file, call, system }

enum ChatMessageStatus { sending, sent, delivered, read, failed, deleted }

enum MessageEncryptionState { plain, encrypted, decryptionFailed }

const Object _unset = Object();

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.clientMessageId,
    required this.kind,
    required this.status,
    required this.encryptionState,
    required this.createdAt,
    this.text,
    List<Attachment> attachments = const [],
    this.replyToMessageId,
    this.editedAt,
    this.deletedAt,
    this.failureReason,
  }) : attachments = List.unmodifiable(attachments);

  final String id;
  final String conversationId;
  final String senderId;
  final String clientMessageId;
  final ChatMessageKind kind;
  final ChatMessageStatus status;
  final MessageEncryptionState encryptionState;
  final String? text;
  final List<Attachment> attachments;
  final String? replyToMessageId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? failureReason;

  ChatMessage copyWith({
    ChatMessageStatus? status,
    MessageEncryptionState? encryptionState,
    Object? text = _unset,
    Object? replyToMessageId = _unset,
    Object? editedAt = _unset,
    Object? deletedAt = _unset,
    Object? failureReason = _unset,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      clientMessageId: clientMessageId,
      kind: kind,
      status: status ?? this.status,
      encryptionState: encryptionState ?? this.encryptionState,
      text: identical(text, _unset) ? this.text : text as String?,
      attachments: attachments,
      replyToMessageId: identical(replyToMessageId, _unset)
          ? this.replyToMessageId
          : replyToMessageId as String?,
      createdAt: createdAt,
      editedAt:
          identical(editedAt, _unset) ? this.editedAt : editedAt as DateTime?,
      deletedAt: identical(deletedAt, _unset)
          ? this.deletedAt
          : deletedAt as DateTime?,
      failureReason: identical(failureReason, _unset)
          ? this.failureReason
          : failureReason as String?,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        senderId: json['senderId'] as String,
        clientMessageId: json['clientMessageId'] as String,
        kind: ChatMessageKind.values.byName(json['kind'] as String),
        status: ChatMessageStatus.values.byName(json['status'] as String),
        encryptionState: MessageEncryptionState.values.byName(
          json['encryptionState'] as String? ?? 'plain',
        ),
        text: json['text'] as String?,
        attachments: (json['attachments'] as List<dynamic>? ?? const [])
            .map((value) => Attachment.fromJson(value as Map<String, dynamic>))
            .toList(),
        replyToMessageId: json['replyToMessageId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        editedAt: _dateOrNull(json['editedAt']),
        deletedAt: _dateOrNull(json['deletedAt']),
        failureReason: json['failureReason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'senderId': senderId,
        'clientMessageId': clientMessageId,
        'kind': kind.name,
        'status': status.name,
        'encryptionState': encryptionState.name,
        'text': text,
        'attachments': attachments.map((value) => value.toJson()).toList(),
        'replyToMessageId': replyToMessageId,
        'createdAt': createdAt.toIso8601String(),
        'editedAt': editedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'failureReason': failureReason,
      };

  static DateTime? _dateOrNull(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
