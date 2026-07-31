import '../../../chat/data/dto/api_envelope.dart';

class DeviceDto {
  const DeviceDto({
    required this.id,
    required this.name,
    required this.platform,
    required this.current,
    required this.revoked,
    required this.lastSeenAt,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String platform;
  final bool current;
  final bool revoked;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  factory DeviceDto.fromJson(Object? value) {
    final json = requireJsonMap(value, 'device');
    final id = _requiredString(json, 'id');
    final name = _requiredString(json, 'name');
    final platform = _requiredString(json, 'platform');
    final current = _requiredBool(json, 'current');
    final revoked = _requiredBool(json, 'revoked');
    final createdAt = _requiredDateTime(json, 'created_at');
    final lastSeenAt = _optionalDateTime(json, 'last_seen_at');
    return DeviceDto(
      id: id,
      name: name,
      platform: platform,
      current: current,
      revoked: revoked,
      lastSeenAt: lastSeenAt,
      createdAt: createdAt,
    );
  }
}

List<DeviceDto> parseDeviceListResponse(Object? value) {
  final envelope = ApiEnvelope<List<DeviceDto>>.fromJson(
    requireJsonMap(value, 'device list response'),
    (data) => requireJsonList(data, 'device list')
        .map(DeviceDto.fromJson)
        .toList(growable: false),
  );
  return envelope.data;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('device.$key must be a non-empty string');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('device.$key must be a boolean');
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _optionalDateTime(json, key);
  if (value != null) return value;
  throw FormatException('device.$key must be an ISO-8601 datetime');
}

DateTime? _optionalDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('device.$key must be an ISO-8601 datetime or null');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('device.$key must be an ISO-8601 datetime or null');
  }
  return parsed.toUtc();
}
