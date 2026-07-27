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
    final meta = json['meta'];
    return ApiEnvelope(
      requestId: json['request_id'] as String,
      data: decodeData(json['data']),
      nextCursor:
          meta is Map<String, Object?> ? meta['next_cursor'] as String? : null,
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
