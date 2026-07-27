import '../../models/conversation.dart';

class ConversationDto {
  const ConversationDto({
    required this.id,
    required this.kind,
    required this.title,
    required this.participantIds,
    required this.createdAt,
    required this.updatedAt,
    this.subtitle,
    this.avatarUrl,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.muted = false,
    this.pinned = false,
    this.encryptionScheme,
  });

  final String id;
  final String kind;
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final List<String> participantIds;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool muted;
  final bool pinned;
  final String? encryptionScheme;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ConversationDto.fromJson(Map<String, Object?> json) {
    final memberIds = json['participant_ids'] ?? json['member_ids'];
    return ConversationDto(
      id: json['id'] as String,
      kind: json['kind'] as String,
      title: (json['name'] ?? json['title'] ?? '') as String,
      subtitle: json['subtitle'] as String?,
      avatarUrl: (json['avatar_url'] ?? json['avatar']) as String?,
      participantIds: memberIds is List<Object?>
          ? memberIds.cast<String>()
          : const <String>[],
      lastMessagePreview: json['last_message_preview'] as String?,
      lastMessageAt: _dateOrNull(json['last_message_at']),
      unreadCount: json['unread_count'] as int? ?? 0,
      muted: json['muted'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
      encryptionScheme: json['encryption_scheme'] as String?,
      createdAt: _requiredDate(json['created_at'], 'created_at'),
      updatedAt: _requiredDate(
        json['updated_at'] ?? json['created_at'],
        'updated_at',
      ),
    );
  }

  Conversation toDomain() => Conversation(
        id: id,
        kind: ConversationKind.values.byName(kind),
        title: title,
        subtitle: subtitle,
        avatarUrl: avatarUrl,
        participantIds: participantIds,
        lastMessagePreview: lastMessagePreview,
        lastMessageAt: lastMessageAt,
        unreadCount: unreadCount,
        isMuted: muted,
        isPinned: pinned,
        encryptionState: encryptionScheme == null
            ? ConversationEncryptionState.none
            : ConversationEncryptionState.ready,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static DateTime? _dateOrNull(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  static DateTime _requiredDate(Object? value, String field) {
    if (value is! String) throw FormatException('$field is required');
    return DateTime.parse(value);
  }
}
