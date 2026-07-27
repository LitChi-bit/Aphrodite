class ApiEnvelope<T> {
  const ApiEnvelope(
      {required this.requestId, required this.data, this.nextCursor});

  final String requestId;
  final T data;
  final String? nextCursor;

  factory ApiEnvelope.fromJson(
    Map<String, Object?> json,
    T Function(Object? json) decodeData,
  ) {
    final requestId = json['request_id'];
    if (requestId is! String || requestId.isEmpty) {
      throw const FormatException('request_id must be a non-empty string');
    }
    if (!json.containsKey('data')) {
      throw const FormatException('data is required');
    }

    final metaValue = json['meta'];
    if (metaValue != null && metaValue is! Map<String, Object?>) {
      throw const FormatException('meta must be a JSON object');
    }
    final meta = metaValue as Map<String, Object?>?;
    final nextCursor = meta?['next_cursor'];
    if (nextCursor != null && nextCursor is! String) {
      throw const FormatException('meta.next_cursor must be a string');
    }

    return ApiEnvelope(
      requestId: requestId,
      data: decodeData(json['data']),
      nextCursor: nextCursor as String?,
    );
  }
}

class CursorPage<T> {
  const CursorPage({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;
}

Map<String, Object?> requireJsonMap(Object? value, String context) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$context must be a JSON object');
}

List<Object?> requireJsonList(Object? value, String context) {
  if (value is List<Object?>) return value;
  throw FormatException('$context must be a JSON array');
}
