enum CallKind { audio, video }

enum CallStatus { ringing, active, ended, declined, missed, failed }

class CallSession {
  CallSession({
    required this.id,
    required this.conversationId,
    required this.initiatorId,
    required List<String> participantIds,
    required this.kind,
    required this.status,
    required this.startedAt,
    this.connectedAt,
    this.endedAt,
  }) : participantIds = List.unmodifiable(participantIds);

  final String id;
  final String conversationId;
  final String initiatorId;
  final List<String> participantIds;
  final CallKind kind;
  final CallStatus status;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;

  Duration? get duration {
    if (connectedAt == null || endedAt == null) return null;
    return endedAt!.difference(connectedAt!);
  }

  factory CallSession.fromJson(Map<String, dynamic> json) => CallSession(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        initiatorId: json['initiatorId'] as String,
        participantIds: (json['participantIds'] as List<dynamic>)
            .map((value) => value as String)
            .toList(),
        kind: CallKind.values.byName(json['kind'] as String),
        status: CallStatus.values.byName(json['status'] as String),
        startedAt: DateTime.parse(json['startedAt'] as String),
        connectedAt: _dateOrNull(json['connectedAt']),
        endedAt: _dateOrNull(json['endedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'initiatorId': initiatorId,
        'participantIds': participantIds,
        'kind': kind.name,
        'status': status.name,
        'startedAt': startedAt.toIso8601String(),
        'connectedAt': connectedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
      };

  static DateTime? _dateOrNull(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
