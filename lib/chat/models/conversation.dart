enum ConversationKind { direct, group }

enum ConversationEncryptionState { none, ready, unavailable }

const Object _unset = Object();

class Conversation {
  Conversation({
    required this.id,
    required this.kind,
    required this.title,
    required List<String> participantIds,
    required this.createdAt,
    required this.updatedAt,
    this.subtitle,
    this.avatarUrl,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.encryptionState = ConversationEncryptionState.none,
  }) : participantIds = List.unmodifiable(participantIds);

  final String id;
  final ConversationKind kind;
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final List<String> participantIds;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final ConversationEncryptionState encryptionState;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation copyWith({
    String? title,
    Object? subtitle = _unset,
    Object? avatarUrl = _unset,
    List<String>? participantIds,
    Object? lastMessagePreview = _unset,
    Object? lastMessageAt = _unset,
    int? unreadCount,
    bool? isMuted,
    bool? isPinned,
    ConversationEncryptionState? encryptionState,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id,
      kind: kind,
      title: title ?? this.title,
      subtitle:
          identical(subtitle, _unset) ? this.subtitle : subtitle as String?,
      avatarUrl:
          identical(avatarUrl, _unset) ? this.avatarUrl : avatarUrl as String?,
      participantIds: participantIds ?? this.participantIds,
      lastMessagePreview: identical(lastMessagePreview, _unset)
          ? this.lastMessagePreview
          : lastMessagePreview as String?,
      lastMessageAt: identical(lastMessageAt, _unset)
          ? this.lastMessageAt
          : lastMessageAt as DateTime?,
      unreadCount: unreadCount ?? this.unreadCount,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      encryptionState: encryptionState ?? this.encryptionState,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      kind: ConversationKind.values.byName(json['kind'] as String),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      participantIds: (json['participantIds'] as List<dynamic>)
          .map((value) => value as String)
          .toList(),
      lastMessagePreview: json['lastMessagePreview'] as String?,
      lastMessageAt: _dateOrNull(json['lastMessageAt']),
      unreadCount: json['unreadCount'] as int? ?? 0,
      isMuted: json['isMuted'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      encryptionState: ConversationEncryptionState.values.byName(
        json['encryptionState'] as String? ?? 'none',
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'subtitle': subtitle,
        'avatarUrl': avatarUrl,
        'participantIds': participantIds,
        'lastMessagePreview': lastMessagePreview,
        'lastMessageAt': lastMessageAt?.toIso8601String(),
        'unreadCount': unreadCount,
        'isMuted': isMuted,
        'isPinned': isPinned,
        'encryptionState': encryptionState.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static DateTime? _dateOrNull(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
