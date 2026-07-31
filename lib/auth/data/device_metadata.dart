import 'package:flutter/foundation.dart';

final class DeviceMetadata {
  const DeviceMetadata({required this.name, required this.platform});

  final String name;
  final String platform;

  @override
  bool operator ==(Object other) =>
      other is DeviceMetadata &&
      other.name == name &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(name, platform);

  factory DeviceMetadata.current({
    TargetPlatform? platform,
    bool? isWeb,
  }) {
    final normalizedPlatform = (isWeb ?? kIsWeb)
        ? 'web'
        : _platformName(platform ?? defaultTargetPlatform);
    return DeviceMetadata(
      name: 'Aphrodite ${_displayName(normalizedPlatform)}',
      platform: normalizedPlatform,
    );
  }

  static String _platformName(TargetPlatform platform) => switch (platform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        TargetPlatform.windows => 'windows',
        TargetPlatform.macOS => 'macos',
        TargetPlatform.linux => 'linux',
        TargetPlatform.fuchsia => 'android',
      };

  static String _displayName(String platform) => switch (platform) {
        'android' => 'Android',
        'ios' => 'iOS',
        'windows' => 'Windows',
        'macos' => 'macOS',
        'linux' => 'Linux',
        'web' => 'Web',
        _ => 'Device',
      };
}
