import 'package:aphrodite/auth/data/device_metadata.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps supported native platforms to API values', () {
    expect(
      DeviceMetadata.current(platform: TargetPlatform.android, isWeb: false),
      const DeviceMetadata(name: 'Aphrodite Android', platform: 'android'),
    );
    expect(
      DeviceMetadata.current(platform: TargetPlatform.iOS, isWeb: false),
      const DeviceMetadata(name: 'Aphrodite iOS', platform: 'ios'),
    );
    expect(
      DeviceMetadata.current(platform: TargetPlatform.windows, isWeb: false),
      const DeviceMetadata(name: 'Aphrodite Windows', platform: 'windows'),
    );
    expect(
      DeviceMetadata.current(platform: TargetPlatform.macOS, isWeb: false),
      const DeviceMetadata(name: 'Aphrodite macOS', platform: 'macos'),
    );
    expect(
      DeviceMetadata.current(platform: TargetPlatform.linux, isWeb: false),
      const DeviceMetadata(name: 'Aphrodite Linux', platform: 'linux'),
    );
  });

  test('maps web independently from the host target platform', () {
    expect(
      DeviceMetadata.current(platform: TargetPlatform.windows, isWeb: true),
      const DeviceMetadata(name: 'Aphrodite Web', platform: 'web'),
    );
  });
}
