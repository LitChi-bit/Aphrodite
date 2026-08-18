import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:path_provider/path_provider.dart';

import '../auth/data/auth_api.dart';
import '../auth/data/auth_repository.dart';
import '../auth/data/device_api.dart';
import '../auth/data/device_metadata.dart';
import '../auth/data/secure_device_identity_provider.dart';
import '../auth/data/token_store.dart';
import '../auth/models/auth_session.dart';
import '../chat/data/mls_api.dart';
import '../chat/e2ee/mls_lifecycle_coordinator.dart';
import '../chat/e2ee/native_openmls_loader.dart';
import '../chat/e2ee/native_openmls_session.dart';
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

final deviceApiProvider = Provider<DeviceApi>(
  (Ref ref) => DeviceApi(networkClient: ref.watch(networkClientProvider)),
);

final apiAuthRepositoryProvider = Provider<ApiAuthRepository>(
  (Ref ref) => ApiAuthRepository(
    authApi: ref.watch(authApiProvider),
    deviceIdentityProvider: ref.watch(deviceIdentityProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    authSession: ref.watch(authSessionProvider),
  ),
);

final mlsApiProvider = Provider<MlsApi>(
  (Ref ref) => MlsApi(networkClient: ref.watch(networkClientProvider)),
);

final nativeOpenMlsSessionProvider =
    FutureProvider.autoDispose<NativeOpenMlsSession>((ref) async {
  final supportDirectory = await getApplicationSupportDirectory();
  final session = NativeOpenMlsSession(
    bindings: loadNativeOpenMlsBindings(),
    appSupportDir: validateNativeOpenMlsSupportDirectory(
      supportDirectory.path,
    ),
  )..open();
  ref.onDispose(() => unawaited(session.close()));
  final identity = await ref.read(deviceIdentityProvider).getOrCreate();
  await session.initializeDevice(deviceId: identity.deviceId);
  return session;
});

final mlsLifecycleCoordinatorProvider =
    FutureProvider.autoDispose<MlsLifecycleCoordinator>((ref) async {
  final native = await ref.watch(nativeOpenMlsSessionProvider.future);
  return MlsLifecycleCoordinator(
    api: ref.watch(mlsApiProvider),
    native: native,
  );
});

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
