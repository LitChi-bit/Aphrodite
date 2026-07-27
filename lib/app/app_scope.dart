import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_network_client.dart';
import '../core/network/network_client.dart';
import '../core/storage/flutter_secure_store.dart';
import '../core/storage/secure_store.dart';

final Provider<NetworkClient> networkClientProvider = Provider<NetworkClient>(
  (Ref ref) => DioNetworkClient(baseUrl: 'https://localhost'),
);

final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (Ref ref) => FlutterSecureStore(),
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
