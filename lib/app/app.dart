import 'package:flutter/material.dart';

import 'app_router.dart';
import 'app_theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aphrodite',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: AppRouter.login,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
