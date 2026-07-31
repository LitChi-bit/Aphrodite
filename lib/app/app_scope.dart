import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/data/auth_api.dart';
import '../auth/data/auth_repository.dart';
import '../auth/data/device_metadata.dart';
import '../auth/data/secure_device_identity_provider.dart';
import '../auth/data/token_store.dart';
import '../auth/models/auth_session.dart';
import '../core/network/dio_network_client.dart';
import '../core/network/network_client.dart';
import '../core/storage/flutter_secure_store.dart';
import '../core/storage/secure_store.dart';

final apiBaseUrlProvider = Provider<String>((Ref ref) => 'https://localhost');

final Provider<AuthSession> authSessionProvider = Provider<AuthSession>(
  (Ref ref) => InMemoryAuthSession(),
);

final Provider<NetworkClient> networkClientProvider = Provider<NetworkClient>(
  (Ref ref) => DioNetworkClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    accessTokenProvider: ref.watch(authSessionProvider),
    accessTokenRefresher: () => ref.read(authSessionProvider).refresher,
  ),
);

final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (Ref ref) => FlutterSecureStore(),
);

final tokenStoreProvider = Provider<TokenStore>(
  (Ref ref) => TokenStore(secureStore: ref.watch(secureStoreProvider)),
);

final deviceMetadataProvider = Provider<DeviceMetadata>(
  (Ref ref) => DeviceMetadata.current(),
);

final deviceNameProvider = Provider<String>(
  (Ref ref) => ref.watch(deviceMetadataProvider).name,
);

final devicePlatformProvider = Provider<String>(
  (Ref ref) => ref.watch(deviceMetadataProvider).platform,
);

final deviceIdentityProvider = Provider<DeviceIdentityProvider>(
  (Ref ref) => SecureDeviceIdentityProvider(
    secureStore: ref.watch(secureStoreProvider),
    deviceName: ref.watch(deviceNameProvider),
    platform: ref.watch(devicePlatformProvider),
  ),
);

final authApiProvider = Provider<AuthApi>(
  (Ref ref) => AuthApi(networkClient: ref.watch(networkClientProvider)),
);

final apiAuthRepositoryProvider = Provider<ApiAuthRepository>(
  (Ref ref) => ApiAuthRepository(
    authApi: ref.watch(authApiProvider),
    deviceIdentityProvider: ref.watch(deviceIdentityProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    authSession: ref.watch(authSessionProvider),
  ),
);

class AppScope extends StatelessWidget {
  const AppScope({required this.child, this.overrides = const [], super.key});

  final Widget child;
  final List<Override> overrides;

  @override
  Widget build(BuildContext context) => ProviderScope(
        overrides: overrides,
        child: child,
      );
}
