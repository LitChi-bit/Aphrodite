import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_scope.dart';
import 'auth/providers/auth_provider.dart';

const _useRealAuth = bool.fromEnvironment('APHRODITE_USE_REAL_AUTH');
const _apiBaseUrl = String.fromEnvironment('APHRODITE_API_BASE_URL');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final apiUri = Uri.tryParse(_apiBaseUrl);
  if (_useRealAuth &&
      (apiUri == null || apiUri.scheme != 'https' || apiUri.host.isEmpty)) {
    throw StateError(
      'APHRODITE_API_BASE_URL must be an absolute HTTPS URL when real auth is enabled.',
    );
  }

  runApp(
    AppScope(
      overrides: [
        if (_useRealAuth) ...[
          apiBaseUrlProvider.overrideWithValue(_apiBaseUrl),
          authRepositoryProvider.overrideWith(
            (ref) => ref.watch(apiAuthRepositoryProvider),
          ),
        ],
      ],
      child: const App(),
    ),
  );
}
