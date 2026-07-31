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
      id: _requiredString(json['id'], 'id'),
      kind: _requiredKind(json['kind']),
      title: _requiredString(json['name'] ?? json['title'], 'name'),
      subtitle: _optionalString(json['subtitle'], 'subtitle'),
      avatarUrl:
          _optionalString(json['avatar_url'] ?? json['avatar'], 'avatar_url'),
      participantIds: _stringList(memberIds, 'participant_ids'),
      lastMessagePreview:
          _optionalString(json['last_message_preview'], 'last_message_preview'),
      lastMessageAt: _dateOrNull(json['last_message_at'], 'last_message_at'),
      unreadCount: _nonNegativeInt(json['unread_count'], 'unread_count'),
      muted: _boolOrDefault(json['muted'], 'muted'),
      pinned: _boolOrDefault(json['pinned'], 'pinned'),
      encryptionScheme:
          _optionalString(json['encryption_scheme'], 'encryption_scheme'),
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

  static String _requiredKind(Object? value) {
    final kind = _requiredString(value, 'kind');
    if (!ConversationKind.values.any((candidate) => candidate.name == kind)) {
      throw const FormatException('kind is invalid');
    }
    return kind;
  }

  static List<String> _stringList(Object? value, String field) {
    if (value is! List<Object?>) throw FormatException('$field must be a list');
    return List<String>.unmodifiable(
      value.map((item) => _requiredString(item, field)),
    );
  }

  static int _nonNegativeInt(Object? value, String field) {
    if (value == null) return 0;
    if (value is! int || value < 0) {
      throw FormatException('$field must be a non-negative integer');
    }
    return value;
  }

  static bool _boolOrDefault(Object? value, String field) {
    if (value == null) return false;
    if (value is! bool) throw FormatException('$field must be a boolean');
    return value;
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
