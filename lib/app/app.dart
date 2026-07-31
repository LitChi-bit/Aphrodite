import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/models/auth_state.dart';
import '../auth/providers/auth_provider.dart';
import '../auth/screens/login_screen.dart';
import '../chat/widgets/chat_list_screen.dart';
import 'app_router.dart';
import 'app_theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    return MaterialApp(
      title: 'Aphrodite',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: switch (authState.status) {
        AuthStatus.restoring => const _RestoringSessionScreen(),
        AuthStatus.signedOut ||
        AuthStatus.authenticating =>
          const LoginScreen(),
        AuthStatus.signedIn => const ChatListScreen(),
      },
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}

class _RestoringSessionScreen extends StatelessWidget {
  const _RestoringSessionScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
