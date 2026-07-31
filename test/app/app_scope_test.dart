import 'package:aphrodite/app/app_scope.dart';
import 'package:aphrodite/auth/data/auth_repository.dart';
import 'package:aphrodite/auth/data/device_metadata.dart';
import 'package:aphrodite/auth/models/auth_session.dart';
import 'package:aphrodite/auth/providers/auth_provider.dart';
import 'package:aphrodite/core/network/network_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default authentication remains the demo repository', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(authRepositoryProvider), isA<DemoAuthRepository>());
  });

  test('device metadata can be overridden without changing identity storage',
      () {
    final container = ProviderContainer(
      overrides: [
        deviceMetadataProvider.overrideWithValue(
          const DeviceMetadata(name: 'Aphrodite test', platform: 'ios'),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(deviceNameProvider), 'Aphrodite test');
    expect(container.read(devicePlatformProvider), 'ios');
  });

  test('network client shares the configured in-memory auth session', () {
    final session = InMemoryAuthSession();
    final container = ProviderContainer(
      overrides: [authSessionProvider.overrideWithValue(session)],
    );
    addTearDown(container.dispose);

    expect(container.read(authSessionProvider), same(session));
    expect(container.read(networkClientProvider), isA<NetworkClient>());
  });
}
